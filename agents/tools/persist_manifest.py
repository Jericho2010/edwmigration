#!/usr/bin/env python3
"""Persist Gate migration_manifest.json + ops.migration_manifest_current.

Usage:
  python3 agents/tools/persist_manifest.py --run-id UUID --from-file path.json
  python3 agents/tools/persist_manifest.py --run-id UUID --from-file path.json --skip-ops
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "agents" / "contracts" / "migration_manifest.schema.json"


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


def validate_manifest(doc: dict) -> list[str]:
    schema = json.loads(SCHEMA_PATH.read_text())
    try:
        from jsonschema import Draft7Validator
    except ImportError:
        for key in ("run_id", "gate", "blockers", "converted_artifacts", "attempt"):
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


def upsert_ops(catalog: str, doc: dict) -> None:
    summary = doc.get("summary") or {}
    run_id = esc_sql(str(doc["run_id"]))
    gate = esc_sql(str(doc["gate"]))
    tables_total = int(summary.get("tables_total") or 0)
    tables_landed = int(summary.get("tables_landed") or 0)
    procs_total = int(summary.get("procs_total") or 0)
    procs_converted = int(summary.get("procs_converted") or 0)
    summary_json = esc_sql(json.dumps(summary, separators=(",", ":")))

    sql = (
        f"DELETE FROM `{catalog}`.ops.migration_manifest_current WHERE true;\n"
        f"INSERT INTO `{catalog}`.ops.migration_manifest_current "
        f"(run_id, gate, tables_total, tables_landed, procs_total, procs_converted, "
        f"summary_json, updated_at) VALUES "
        f"('{run_id}', '{gate}', {tables_total}, {tables_landed}, "
        f"{procs_total}, {procs_converted}, '{summary_json}', current_timestamp());"
    )
    run_ops_sql(sql)


def main() -> int:
    load_env()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--from-file", required=True)
    ap.add_argument("--skip-ops", action="store_true")
    args = ap.parse_args()

    src = Path(args.from_file)
    if not src.is_absolute():
        src = ROOT / src
    if not src.is_file():
        print(f"[persist_manifest] file not found: {src}", file=sys.stderr)
        return 1

    doc = json.loads(src.read_text())
    if not isinstance(doc, dict):
        print("[persist_manifest] expected JSON object", file=sys.stderr)
        return 1

    # Prefer CLI run_id if file omits / mismatches
    if "run_id" not in doc:
        doc["run_id"] = args.run_id
    elif str(doc["run_id"]) != args.run_id:
        print(
            f"[persist_manifest] WARN file run_id={doc['run_id']} "
            f"!= --run-id {args.run_id}; using CLI run_id",
            file=sys.stderr,
        )
        doc["run_id"] = args.run_id

    errors = validate_manifest(doc)
    if errors:
        print("[persist_manifest] schema validation failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    run_dir = ROOT / "agents" / "out" / args.run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    out_path = run_dir / "migration_manifest.json"

    if not args.skip_ops:
        try:
            catalog = load_context_catalog(run_dir)
            upsert_ops(catalog, doc)
        except Exception as exc:  # noqa: BLE001
            print(f"[persist_manifest] ERROR ops upsert failed: {exc}", file=sys.stderr)
            return 1

    out_path.write_text(json.dumps(doc, indent=2) + "\n")
    print(
        f"[persist_manifest] run_id={args.run_id} gate={doc.get('gate')} "
        f"path={out_path} ops={'skipped' if args.skip_ops else 'ok'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
