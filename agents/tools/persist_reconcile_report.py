#!/usr/bin/env python3
"""Persist Test reconcile_report.json (schema-validated). Disk only — no ops upsert.

Usage:
  python3 agents/tools/persist_reconcile_report.py --run-id UUID --from-file path.json
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "agents" / "contracts" / "reconcile_report.schema.json"


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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--from-file", required=True)
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
    out_path.write_text(json.dumps(doc, indent=2) + "\n")

    summary = doc.get("summary") or {}
    _enqueue_metric(args.run_id, "reconcile_passed", float(summary.get("passed") or 0))
    _enqueue_metric(args.run_id, "reconcile_failed", float(summary.get("failed") or 0))
    print(
        f"[persist_reconcile_report] run_id={args.run_id} "
        f"passed={summary.get('passed')} failed={summary.get('failed')} "
        f"path={out_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
