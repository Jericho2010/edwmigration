#!/usr/bin/env python3
"""Ensure early agent_events for Gate rule 4 on table-only runs.

Writes coordinator/started always; convert/skipped when procs_total==0
or routines_skipped_reason is set. Also best-effort inits MLflow observe
(agents/tools/mlflow_observe.py) for live traces.

Does **not** record assess/completed — coordinator records that after
persist_backlog.py succeeds.

Usage: python3 agents/tools/ensure_run_events.py --run-id UUID
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


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


def record(run_id: str, agent: str, event: str, detail: str = "") -> None:
    cmd = [
        str(ROOT / "agents" / "tools" / "record_agent_event.sh"),
        "--run-id",
        run_id,
        "--agent",
        agent,
        "--event",
        event,
    ]
    if detail:
        cmd.extend(["--detail", detail])
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        print(proc.stderr or proc.stdout, file=sys.stderr)
        raise SystemExit(proc.returncode)


def init_mlflow(run_id: str) -> None:
    """Best-effort MLflow run + root span; print observe_url when enabled."""
    tools = str(ROOT / "agents" / "tools")
    if tools not in sys.path:
        sys.path.insert(0, tools)
    try:
        import mlflow_observe as mobs  # noqa: WPS433 — local tool module

        data = mobs.init_run(run_id, root=ROOT)
        mobs.announce_observe_url(str(data.get("observe_url") or ""))
    except Exception:
        pass


def main() -> int:
    load_env()
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-id", required=True)
    args = ap.parse_args()

    inv_path = ROOT / "agents" / "out" / args.run_id / "inventory.json"
    procs_total = 0
    skip_reason = ""
    if inv_path.is_file():
        inv = json.loads(inv_path.read_text())
        procs_total = int(inv.get("procs_total") or 0)
        skip_reason = inv.get("routines_skipped_reason") or ""

    init_mlflow(args.run_id)
    record(args.run_id, "coordinator", "started", "ensure_run_events")

    if procs_total == 0 or skip_reason:
        detail = skip_reason or "no backlog / routines skipped"
        record(args.run_id, "convert", "skipped", detail)

    print(f"[ensure_run_events] run_id={args.run_id} procs_total={procs_total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
