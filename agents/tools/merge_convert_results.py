#!/usr/bin/env python3
"""Merge parallel convert results into backlog + ops.proc_conversion_map.

Reads agents/out/<run_id>/convert/<item_id>.json, updates migration_backlog.json
statuses, writes convert_summary.json, and upserts proc_conversion_map.

Ops upsert runs *before* rewriting backlog on disk. On ops failure, writes
merge_failed.json and leaves the previous backlog unchanged.

Usage:
  python3 agents/tools/merge_convert_results.py --run-id UUID
  python3 agents/tools/merge_convert_results.py --run-id UUID --skip-ops
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "agents" / "contracts" / "convert_result.schema.json"
OK_STATUSES = {"draft", "review", "final"}
BACKLOG_CONVERTED = {"draft", "review", "final"}


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


def validate_result(doc: dict, schema: dict) -> list[str]:
    try:
        from jsonschema import Draft7Validator
    except ImportError:
        errors = []
        for key in schema.get("required", []):
            if key not in doc:
                errors.append(f"missing required property: {key}")
        status = doc.get("status")
        if status and status not in schema["properties"]["status"]["enum"]:
            errors.append(f"invalid status: {status}")
        return errors
    return [e.message for e in Draft7Validator(schema).iter_errors(doc)]


def load_context_catalog(run_dir: Path) -> str:
    ctx_path = run_dir / "context.json"
    if ctx_path.is_file():
        ctx = json.loads(ctx_path.read_text())
        cat = ctx.get("uc_catalog")
        if cat:
            return str(cat)
    return os.environ.get("DATABRICKS_CATALOG", "edw_migration")


def convertible_items(backlog: list[dict]) -> list[dict]:
    items = []
    for item in backlog:
        status = (item.get("status") or "").lower()
        layer = (item.get("target_layer") or "").lower()
        if status in {"done", "n/a"} or layer == "n/a":
            continue
        items.append(item)
    return items


def run_ops_sql(sql: str) -> None:
    cmd = [str(ROOT / "agents" / "tools" / "run_sql.sh"), "--sql", sql]
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        print(proc.stderr or proc.stdout, file=sys.stderr)
        raise RuntimeError(proc.stderr or proc.stdout or "run_sql failed")


def upsert_proc_map(catalog: str, rows: list[dict]) -> None:
    if not rows:
        return
    statements: list[str] = []
    for row in rows:
        lp = esc_sql(row["legacy_proc"])
        tp = esc_sql(row["target_path"])
        st = esc_sql(row["status"])
        statements.append(
            f"DELETE FROM `{catalog}`.ops.proc_conversion_map "
            f"WHERE legacy_proc = '{lp}';"
        )
        statements.append(
            f"INSERT INTO `{catalog}`.ops.proc_conversion_map "
            f"(legacy_proc, target_path, status, updated_at) VALUES "
            f"('{lp}', '{tp}', '{st}', current_timestamp());"
        )
    run_ops_sql("\n".join(statements))


def merge(run_id: str, skip_ops: bool = False) -> dict:
    run_dir = ROOT / "agents" / "out" / run_id
    backlog_path = run_dir / "migration_backlog.json"
    convert_dir = run_dir / "convert"
    failed_path = run_dir / "merge_failed.json"
    schema = json.loads(SCHEMA_PATH.read_text())

    if not backlog_path.is_file():
        raise FileNotFoundError(f"backlog not found: {backlog_path}")

    backlog = json.loads(backlog_path.read_text())
    if not isinstance(backlog, list):
        raise ValueError("migration_backlog.json must be a JSON array")

    # Deep-ish copy so we can abandon writes on ops failure
    backlog = json.loads(json.dumps(backlog))
    items = convertible_items(backlog)

    converted = 0
    blocked = 0
    missing = 0
    map_rows: list[dict] = []
    details: list[dict] = []

    for item in items:
        item_id = item["item_id"]
        result_path = convert_dir / f"{item_id}.json"
        entry: dict = {"item_id": item_id, "legacy_proc": item.get("legacy_proc")}

        if not result_path.is_file():
            missing += 1
            blocked += 1
            item["status"] = "blocked"
            entry.update(
                {
                    "status": "blocked",
                    "notes": "missing convert result file",
                    "target_path": item.get("target_path"),
                }
            )
            details.append(entry)
            continue

        doc = json.loads(result_path.read_text())
        schema_errors = validate_result(doc, schema)
        if schema_errors:
            blocked += 1
            item["status"] = "blocked"
            entry.update(
                {
                    "status": "blocked",
                    "notes": "invalid convert result: " + "; ".join(schema_errors),
                    "target_path": doc.get("target_path") or item.get("target_path"),
                }
            )
            details.append(entry)
            continue

        if doc.get("item_id") != item_id:
            blocked += 1
            item["status"] = "blocked"
            entry.update(
                {
                    "status": "blocked",
                    "notes": f"result item_id {doc.get('item_id')!r} != backlog {item_id!r}",
                    "target_path": doc.get("target_path"),
                }
            )
            details.append(entry)
            continue

        target_path = doc["target_path"]
        status = doc["status"]
        on_disk = (ROOT / target_path).is_file()

        if status in OK_STATUSES and not on_disk:
            blocked += 1
            item["status"] = "blocked"
            entry.update(
                {
                    "status": "blocked",
                    "notes": f"target_path missing on disk: {target_path}",
                    "target_path": target_path,
                }
            )
            details.append(entry)
            continue

        if status == "blocked":
            blocked += 1
            item["status"] = "blocked"
        elif status in BACKLOG_CONVERTED:
            converted += 1
            item["status"] = "converted"
        else:
            blocked += 1
            item["status"] = "blocked"

        if status in OK_STATUSES:
            item["target_path"] = target_path

        map_status = status if status in OK_STATUSES or status == "blocked" else "blocked"
        map_rows.append(
            {
                "legacy_proc": doc["legacy_proc"],
                "target_path": target_path,
                "status": map_status,
            }
        )
        entry.update(
            {
                "status": map_status,
                "notes": doc.get("notes", ""),
                "target_path": target_path,
                "patterns_used": doc.get("patterns_used", []),
            }
        )
        details.append(entry)

    summary = {
        "run_id": run_id,
        "converted": converted,
        "blocked": blocked,
        "missing_results": missing,
        "total": len(items),
        "merged_at": datetime.now(timezone.utc).isoformat(),
        "items": details,
    }

    if not skip_ops:
        try:
            catalog = load_context_catalog(run_dir)
            upsert_proc_map(catalog, map_rows)
        except Exception as exc:  # noqa: BLE001 — surface ops failure to marker
            marker = {
                "run_id": run_id,
                "error": str(exc),
                "failed_at": datetime.now(timezone.utc).isoformat(),
                "note": "ops.proc_conversion_map upsert failed; backlog not updated",
                "pending_summary": summary,
            }
            failed_path.write_text(json.dumps(marker, indent=2) + "\n")
            print(
                f"[merge_convert_results] ERROR: ops upsert failed; "
                f"wrote {failed_path}; backlog unchanged",
                file=sys.stderr,
            )
            raise SystemExit(1) from exc

    backlog_path.write_text(json.dumps(backlog, indent=2) + "\n")
    summary_path = run_dir / "convert_summary.json"
    summary_path.write_text(json.dumps(summary, indent=2) + "\n")
    if failed_path.is_file():
        failed_path.unlink()

    print(
        f"[merge_convert_results] run_id={run_id} converted={converted} "
        f"blocked={blocked} missing={missing} total={len(items)} "
        f"summary={summary_path}"
    )
    return summary


def main() -> int:
    load_env()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", required=True)
    ap.add_argument(
        "--skip-ops",
        action="store_true",
        help="Update local JSON only; do not call Databricks for proc_conversion_map",
    )
    args = ap.parse_args()

    try:
        merge(args.run_id, skip_ops=args.skip_ops)
    except SystemExit:
        raise
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"[merge_convert_results] ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
