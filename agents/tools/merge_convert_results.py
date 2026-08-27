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


def upsert_proc_map(catalog: str, rows: list[dict], run_id: str = "") -> None:
    if not rows:
        return
    rid = esc_sql(run_id)
    statements: list[str] = []
    for row in rows:
        lp = esc_sql(row["legacy_proc"])
        tp = esc_sql(row["target_path"])
        st = esc_sql(row["status"])
        statements.append(
            f"DELETE FROM `{catalog}`.ops.proc_conversion_map "
            f"WHERE run_id = '{rid}' AND legacy_proc = '{lp}';"
        )
        statements.append(
            f"INSERT INTO `{catalog}`.ops.proc_conversion_map "
            f"(legacy_proc, target_path, status, updated_at, run_id) VALUES "
            f"('{lp}', '{tp}', '{st}', current_timestamp(), '{rid}');"
        )
    run_ops_sql("\n".join(statements))


def load_wave(run_dir: Path) -> dict | None:
    path = run_dir / "convert_wave.json"
    if not path.is_file():
        return None
    doc = json.loads(path.read_text())
    if not isinstance(doc, dict):
        raise ValueError("convert_wave.json must be a JSON object")
    return doc


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

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from assert_watchable import fail_if_unwatchable

    watch_err = fail_if_unwatchable(
        run_id,
        "Convert",
        root=ROOT,
        require_mlflow=False if skip_ops else None,
    )
    if watch_err:
        marker = {
            "run_id": run_id,
            "error": "watchable: " + "; ".join(watch_err),
            "failed_at": datetime.now(timezone.utc).isoformat(),
            "note": "hook subagentStart missing; backlog not updated — re-launch edw-convert",
        }
        failed_path.write_text(json.dumps(marker, indent=2) + "\n")
        print(
            f"[merge_convert_results] ERROR: watchable check failed; "
            f"wrote {failed_path}; backlog unchanged",
            file=sys.stderr,
        )
        raise SystemExit(1)

    # Deep-ish copy so we can abandon writes on ops failure
    backlog = json.loads(json.dumps(backlog))
    items = convertible_items(backlog)
    wave = load_wave(run_dir)
    wave_ids: set[str] | None = None
    wave_paths: set[str] = set()
    if wave is not None:
        raw_ids = wave.get("item_ids") or wave.get("items") or []
        wave_ids = {str(x) for x in raw_ids}
        for p in wave.get("target_paths") or []:
            wave_paths.add(str(p))
        if not wave_ids and wave_paths:
            wave_ids = {
                str(it["item_id"])
                for it in items
                if str(it.get("target_path") or "") in wave_paths
            }

    converted = 0
    blocked = 0
    missing = 0
    map_rows: list[dict] = []
    details: list[dict] = []

    by_id = {str(it.get("item_id")): it for it in items}

    if wave_ids is not None:
        for wid in sorted(wave_ids):
            item = by_id.get(wid)
            result_path = convert_dir / f"{wid}.json"
            tp = (item or {}).get("target_path") or ""
            if tp:
                wave_paths.add(str(tp))
            if not result_path.is_file():
                raise FileNotFoundError(
                    f"wave item {wid} missing convert/{wid}.json "
                    f"(target_path={tp or 'unknown'})"
                )

    work_items = items
    if wave_ids is not None:
        work_items = [it for it in items if str(it.get("item_id")) in wave_ids]

    for item in work_items:
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
        expected_tp = item.get("target_path") or ""
        if expected_tp and target_path != expected_tp:
            blocked += 1
            item["status"] = "blocked"
            entry.update(
                {
                    "status": "blocked",
                    "notes": f"JSON target_path {target_path!r} != backlog {expected_tp!r}",
                    "target_path": target_path,
                }
            )
            details.append(entry)
            continue

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
        "total": len(work_items),
        "merged_at": datetime.now(timezone.utc).isoformat(),
        "items": details,
    }

    if not skip_ops:
        try:
            catalog = load_context_catalog(run_dir)
            upsert_proc_map(catalog, map_rows, run_id=run_id)
            sys.path.insert(0, str(ROOT / "agents" / "tools"))
            from persist_backlog import upsert_ops as upsert_backlog

            upsert_backlog(catalog, backlog, run_id=run_id)
        except Exception as exc:  # noqa: BLE001 — surface ops failure to marker
            marker = {
                "run_id": run_id,
                "error": str(exc),
                "failed_at": datetime.now(timezone.utc).isoformat(),
                "note": "ops.proc_conversion_map / migration_backlog upsert failed; backlog not updated",
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

    _enqueue_metric(run_id, "procs_converted", float(converted))
    _enqueue_metric(run_id, "procs_blocked", float(blocked))

    sys.path.insert(0, str(ROOT / "agents" / "tools"))
    from edw_handoff import emit_handoff_quiet

    if missing:
        oc = "fail"
    elif blocked:
        oc = "blocked"
    else:
        oc = "ok"
    emit_handoff_quiet(
        run_id,
        from_agent="convert",
        to_agent="coordinator",
        item_id="",
        action="merge",
        artifact=str(summary_path.relative_to(ROOT)),
        outcome=oc,
        skip_ops=skip_ops,
    )

    print(
        f"[merge_convert_results] run_id={run_id} converted={converted} "
        f"blocked={blocked} missing={missing} total={len(work_items)} "
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
