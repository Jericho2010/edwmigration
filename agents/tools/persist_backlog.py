#!/usr/bin/env python3
"""Persist Assess backlog to disk + ops.migration_backlog.

Accepts a JSON array (schema) or Assess wrapper {migration_backlog, assess_summary}.

Usage:
  python3 agents/tools/persist_backlog.py --run-id UUID --from-file path.json
  python3 agents/tools/persist_backlog.py --run-id UUID --from-file path.json --skip-ops
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "agents" / "contracts" / "migration_backlog.schema.json"


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


def validate_backlog(backlog: list) -> list[str]:
    schema = json.loads(SCHEMA_PATH.read_text())
    try:
        from jsonschema import Draft7Validator
    except ImportError:
        if not isinstance(backlog, list):
            return ["migration_backlog must be a JSON array"]
        return []
    return [e.message for e in Draft7Validator(schema).iter_errors(backlog)]


def unwrap(doc: object) -> tuple[list, str]:
    if isinstance(doc, list):
        return doc, ""
    if isinstance(doc, dict):
        bl = doc.get("migration_backlog")
        if not isinstance(bl, list):
            raise ValueError("wrapper must contain migration_backlog array")
        summary = doc.get("assess_summary") or ""
        return bl, str(summary)
    raise ValueError("expected JSON array or {migration_backlog, assess_summary}")


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


def upsert_ops(catalog: str, backlog: list[dict]) -> None:
    statements: list[str] = [
        f"DELETE FROM `{catalog}`.ops.migration_backlog WHERE true;"
    ]
    for item in backlog:
        statements.append(
            f"INSERT INTO `{catalog}`.ops.migration_backlog "
            f"(item_id, legacy_proc, classification, reads, writes, "
            f"target_layer, target_path, priority, risk_flags, status, updated_at) VALUES "
            f"('{esc_sql(str(item.get('item_id', '')))}', "
            f"'{esc_sql(str(item.get('legacy_proc', '')))}', "
            f"'{esc_sql(str(item.get('classification', '')))}', "
            f"'{esc_sql(str(item.get('reads', '')))}', "
            f"'{esc_sql(str(item.get('writes', '')))}', "
            f"'{esc_sql(str(item.get('target_layer', '')))}', "
            f"'{esc_sql(str(item.get('target_path', '')))}', "
            f"'{esc_sql(str(item.get('priority', '')))}', "
            f"'{esc_sql(str(item.get('risk_flags', '')))}', "
            f"'{esc_sql(str(item.get('status', 'pending')))}', "
            f"current_timestamp());"
        )
    run_ops_sql("\n".join(statements))


def main() -> int:
    load_env()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--from-file", required=True, help="Assess JSON array or wrapper")
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
        print(f"[persist_backlog] file not found: {src}", file=sys.stderr)
        return 1

    backlog, summary = unwrap(json.loads(src.read_text()))
    errors = validate_backlog(backlog)
    if errors:
        print("[persist_backlog] schema validation failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    run_dir = ROOT / "agents" / "out" / args.run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    out_path = run_dir / "migration_backlog.json"

    if not args.skip_ops:
        try:
            catalog = load_context_catalog(run_dir)
            upsert_ops(catalog, backlog)
        except Exception as exc:  # noqa: BLE001
            print(f"[persist_backlog] ERROR ops upsert failed: {exc}", file=sys.stderr)
            return 1

    out_path.write_text(json.dumps(backlog, indent=2) + "\n")
    if summary:
        (run_dir / "assess_summary.md").write_text(summary.rstrip() + "\n")

    print(
        f"[persist_backlog] run_id={args.run_id} items={len(backlog)} "
        f"path={out_path} ops={'skipped' if args.skip_ops else 'ok'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
