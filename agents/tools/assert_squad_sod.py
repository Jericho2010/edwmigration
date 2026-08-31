#!/usr/bin/env python3
"""Fail-closed SoD: coordinator must not write silver/gold; convert needs wave lock.

Called from afterFileEdit hook. Writes agents/out/<run_id>/sod_violation on FAIL.

Usage:
  python3 agents/tools/assert_squad_sod.py --run-id UUID --agent coordinator --file databricks/gold/40_x.sql
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

MIGRATE_PREFIX = ("databricks/silver/", "databricks/gold/")


def is_layer_sql(path: str) -> bool:
    p = path.replace("\\", "/")
    return any(x in p for x in MIGRATE_PREFIX) and p.endswith(".sql")


def check(agent: str, file_path: str, run_id: str, root: Path | None = None) -> str | None:
    root = root or ROOT
    rel = file_path.replace("\\", "/")
    if "databricks/" in rel:
        rel = "databricks/" + rel.split("databricks/", 1)[1]
    if not is_layer_sql(rel):
        return None
    ag = (agent or "").lower()
    wave_path = root / "agents" / "out" / run_id / "convert_wave.json"
    wave_paths: set[str] = set()
    if wave_path.is_file():
        try:
            wave = json.loads(wave_path.read_text())
        except json.JSONDecodeError:
            wave = None
        else:
            wave_paths = {str(p).replace("\\", "/") for p in (wave.get("target_paths") or [])}
            for it in wave.get("items") or []:
                if it.get("target_path"):
                    wave_paths.add(str(it["target_path"]).replace("\\", "/"))
    # Cursor afterFileEdit often fires in the parent and maps as coordinator even
    # when an edw-convert Task wrote the file. Wave lock is the SoD evidence.
    if rel in wave_paths:
        return None
    if ag in {"coordinator", "demo-guide", "demo_guide", "start", "assess", "test", "gate"}:
        return f"{ag} must not write {rel}"
    if ag == "convert":
        if not wave_path.is_file():
            return f"convert write {rel} without convert_wave.json"
        return f"convert write {rel} not in convert_wave.json"
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--agent", required=True)
    ap.add_argument("--file", required=True)
    args = ap.parse_args()
    err = check(args.agent, args.file, args.run_id)
    if not err:
        return 0
    run_dir = ROOT / "agents" / "out" / args.run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    marker = run_dir / "sod_violation"
    payload = {
        "run_id": args.run_id,
        "agent": args.agent,
        "file": args.file,
        "error": err,
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    marker.write_text(json.dumps(payload, indent=2) + "\n")
    print(f"[assert_squad_sod] FAIL {err}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
