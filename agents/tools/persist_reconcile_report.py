#!/usr/bin/env python3
"""Persist Test reconcile_report.json (schema-validated) + ops.reconcile_results.

Usage:
  python3 agents/tools/persist_reconcile_report.py --run-id UUID --from-file path.json
  python3 agents/tools/persist_reconcile_report.py --run-id UUID --from-file path.json --skip-ops
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "agents" / "contracts" / "reconcile_report.schema.json"


def load_env() -> None:
    env_path = ROOT / ".env"
    if not env_path.is_file():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def esc_sql(value: str) -> str:
    return value.replace("'", "''")


def validate_report(doc: dict) -> list[str]:
    schema = json.loads(SCHEMA_PATH.read_text())
    try:
        from jsonschema import Draft7Validator
    except ImportError:
        for key in ("run_id", "checks", "summary"):
            if key not in doc:
                return [f"missing required property: {key}"]
        return []
    return [e.message for e in Draft7Validator(schema).iter_errors(doc)]


def load_context_catalog(run_dir: Path) -> str:
    ctx_path = run_dir / "context.json"
    if ctx_path.is_file():
        ctx = json.loads(ctx_path.read_text())
        cat = ctx.get("uc_catalog")
        if cat:
            return str(cat)
    return os.environ.get("DATABRICKS_CATALOG", "edw_migration")


def run_ops_sql(sql: str) -> None:
    cmd = [str(ROOT / "agents" / "tools" / "run_sql.sh"), "--sql", sql]
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        print(proc.stderr or proc.stdout, file=sys.stderr)
        raise RuntimeError(proc.stderr or proc.stdout or "run_sql failed")


def _enqueue_metric(run_id: str, key: str, value: float) -> None:
    observe = ROOT / "agents" / "tools" / "mlflow_observe.py"
    if not observe.is_file():
        return
    subprocess.run(
        [sys.executable, str(observe), "metric", "--run-id", run_id, "--key", key, "--value", str(value)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
        check=False,
    )


def build_upsert_sql(catalog: str, run_id: str, checks: list) -> str:
    rid = esc_sql(run_id)
    statements = [
        f"DELETE FROM `{catalog}`.ops.reconcile_results WHERE run_id = '{rid}';"
    ]
    for ch in checks:
        if not isinstance(ch, dict):
            continue
        statements.append(
            f"INSERT INTO `{catalog}`.ops.reconcile_results "
            f"(check_id, table_name, expected, actual, delta, result, run_id, ts) VALUES "
            f"('{esc_sql(str(ch.get('check_id', '')))}', "
            f"'{esc_sql(str(ch.get('table', '')))}', "
            f"'{esc_sql(str(ch.get('expected', '')))}', "
            f"'{esc_sql(str(ch.get('actual', '')))}', "
            f"'{esc_sql(str(ch.get('delta', '')))}', "
            f"'{esc_sql(str(ch.get('result', '')))}', "
            f"'{rid}', current_timestamp());"
        )
    return "\n".join(statements)


def upsert_ops(catalog: str, doc: dict) -> None:
    run_ops_sql(build_upsert_sql(catalog, str(doc["run_id"]), doc.get("checks") or []))


def main() -> int:
    load_env()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--from-file", required=True)
    ap.add_argument(
        "--skip-ops",
        action="store_true",
        help="Write local JSON only; do not call Databricks",
    )
    args = ap.parse_args()

    src = Path(args.from_file)
    if not src.is_absolute():
        src = ROOT / src
    if not src.is_file():
        print(f"[persist_reconcile_report] file not found: {src}", file=sys.stderr)
        return 1

    doc = json.loads(src.read_text())
    if not isinstance(doc, dict):
        print("[persist_reconcile_report] expected JSON object", file=sys.stderr)
        return 1

    if "run_id" not in doc:
        doc["run_id"] = args.run_id
    elif str(doc["run_id"]) != args.run_id:
        print(
            f"[persist_reconcile_report] WARN file run_id={doc['run_id']} "
            f"!= --run-id {args.run_id}; using CLI run_id",
            file=sys.stderr,
        )
        doc["run_id"] = args.run_id

    errors = validate_report(doc)
    if errors:
        print("[persist_reconcile_report] schema validation failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    run_dir = ROOT / "agents" / "out" / args.run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    out_path = run_dir / "reconcile_report.json"

    if not args.skip_ops:
        try:
            catalog = load_context_catalog(run_dir)
            upsert_ops(catalog, doc)
        except Exception as exc:  # noqa: BLE001
            print(f"[persist_reconcile_report] ERROR ops upsert failed: {exc}", file=sys.stderr)
            return 1

    out_path.write_text(json.dumps(doc, indent=2) + "\n")

    summary = doc.get("summary") or {}
    _enqueue_metric(args.run_id, "reconcile_passed", float(summary.get("passed") or 0))
    _enqueue_metric(args.run_id, "reconcile_failed", float(summary.get("failed") or 0))

    try:
        sys.path.insert(0, str(ROOT / "agents" / "tools"))
        from edw_handoff import emit_handoff_quiet

        failed = int(summary.get("failed") or 0)
        emit_handoff_quiet(
            args.run_id,
            from_agent="test",
            to_agent="coordinator",
            action="persist",
            artifact=str(out_path.relative_to(ROOT)),
            outcome="fail" if failed else "ok",
            skip_ops=args.skip_ops,
        )
    except Exception:
        pass

    print(
        f"[persist_reconcile_report] run_id={args.run_id} "
        f"passed={summary.get('passed')} failed={summary.get('failed')} "
        f"path={out_path} ops={'skipped' if args.skip_ops else 'ok'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
