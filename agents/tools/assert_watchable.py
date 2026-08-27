#!/usr/bin/env python3
"""Fail closed unless Cursor hooks recorded subagentStart for the stage.

Dual_write / record_agent_event completed|start|stop|skipped is not evidence.
Track A (context.track_a) or EDW_OBSERVE_STRICT=1 → exit 1. Otherwise WARN.

Usage:
  python3 agents/tools/assert_watchable.py --run-id UUID --stage Assess|Convert|Test|Gate
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

HOOK_START = "subagentstart"
MILESTONE_EVENTS = {
    "start",
    "stop",
    "started",
    "completed",
    "skipped",
    "failed",
    "handoff",
    "blocked",
}

STAGE_AGENTS: dict[str, list[str]] = {
    "assess": ["assess"],
    "convert": ["convert"],
    "job": ["convert"],
    "test": ["test"],
    "gate": ["gate"],
    "done": ["gate"],
    "mint": [],
    "provision": [],
    "bootstrap": [],
    "setup": [],
    "premint": [],
    "discover": [],
    "land": [],
}


def _truthy(val: str | None) -> bool:
    return (val or "").strip().lower() in {"1", "true", "yes", "on"}


def _falsey(val: str | None) -> bool:
    return (val or "").strip().lower() in {"0", "false", "no", "off"}


def run_dir(run_id: str, root: Path | None = None) -> Path:
    return (root or ROOT) / "agents" / "out" / run_id


def load_context(run_id: str, root: Path | None = None) -> dict:
    path = run_dir(run_id, root) / "context.json"
    if not path.is_file():
        return {}
    try:
        doc = json.loads(path.read_text())
    except json.JSONDecodeError:
        return {}
    return doc if isinstance(doc, dict) else {}


def is_strict(run_id: str, root: Path | None = None, env: dict | None = None) -> bool:
    env = env or os.environ
    if _falsey(env.get("EDW_OBSERVE_STRICT")):
        return False
    if _truthy(env.get("EDW_OBSERVE_STRICT")):
        return True
    ctx = load_context(run_id, root)
    if ctx.get("track_a") is True or _truthy(str(ctx.get("track_a") or "")):
        return True
    if ctx.get("demo_mode") is True or _truthy(str(ctx.get("demo_mode") or "")):
        return True
    return _truthy(env.get("EDW_TRACK_A"))


def is_table_only(run_id: str, root: Path | None = None) -> bool:
    rd = run_dir(run_id, root)
    inv_path = rd / "inventory.json"
    if inv_path.is_file():
        try:
            inv = json.loads(inv_path.read_text())
        except json.JSONDecodeError:
            inv = {}
        if isinstance(inv, dict):
            if inv.get("routines_skipped_reason"):
                return True
            try:
                if int(inv.get("procs_total") or 0) == 0:
                    return True
            except (TypeError, ValueError):
                pass
    bl_path = rd / "migration_backlog.json"
    if not bl_path.is_file():
        return False
    try:
        backlog = json.loads(bl_path.read_text())
    except json.JSONDecodeError:
        return False
    if not isinstance(backlog, list) or not backlog:
        return True
    for item in backlog:
        if not isinstance(item, dict):
            continue
        status = (item.get("status") or "").lower()
        layer = (item.get("target_layer") or "").lower()
        if status in {"done", "n/a"} or layer == "n/a":
            continue
        return False
    return True


def _read_jsonl(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    rows: list[dict] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            doc = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(doc, dict):
            rows.append(doc)
    return rows


def load_hook_events(run_id: str, root: Path | None = None) -> list[dict]:
    return _read_jsonl(run_dir(run_id, root) / "events.buf.jsonl")


def _norm_event(row: dict) -> str:
    return str(row.get("event") or "").strip().lower()


def is_hook_start(row: dict) -> bool:
    ev = _norm_event(row)
    if ev != HOOK_START:
        return False
    if ev in MILESTONE_EVENTS:
        return False
    return True


def hook_starts_for(agent: str, rows: list[dict]) -> list[dict]:
    want = (agent or "").strip().lower()
    return [
        r
        for r in rows
        if is_hook_start(r) and str(r.get("agent") or "").strip().lower() == want
    ]


def _blob(row: dict) -> str:
    parts = [
        str(row.get("detail") or ""),
        str(row.get("tool") or ""),
        str(row.get("sub_id") or row.get("subagent_id") or ""),
        json.dumps(row, default=str),
    ]
    return " ".join(parts)


def wave_item_ids(run_id: str, root: Path | None = None) -> list[str]:
    path = run_dir(run_id, root) / "convert_wave.json"
    if not path.is_file():
        return []
    try:
        wave = json.loads(path.read_text())
    except json.JSONDecodeError:
        return []
    if not isinstance(wave, dict):
        return []
    ids = [str(x) for x in (wave.get("item_ids") or []) if x]
    if ids:
        return ids
    for it in wave.get("items") or []:
        if isinstance(it, dict) and it.get("item_id"):
            ids.append(str(it["item_id"]))
    return ids


def _serve_alive(run_id: str, root: Path | None = None) -> bool | None:
    path = run_dir(run_id, root) / "mlflow_serve.pid"
    if not path.is_file():
        return None
    try:
        pid = int(path.read_text().strip())
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def check_mlflow(
    run_id: str,
    root: Path | None = None,
    *,
    require_serve: bool = True,
) -> list[str]:
    errors: list[str] = []
    ctx_path = run_dir(run_id, root) / "mlflow_context.json"
    if not ctx_path.is_file():
        errors.append("mlflow_context.json missing — run mlflow_observe init / nest-probe")
        return errors
    try:
        ctx = json.loads(ctx_path.read_text())
    except json.JSONDecodeError:
        errors.append("mlflow_context.json is not JSON")
        return errors
    if not isinstance(ctx, dict):
        errors.append("mlflow_context.json is not an object")
        return errors
    if ctx.get("enabled") is not True:
        errors.append("mlflow enabled is not true — Track A must not continue with a lying tree")
    err = str(ctx.get("last_error") or ctx.get("error") or "").strip()
    if err:
        errors.append(f"mlflow last_error={err}")
    if require_serve:
        alive = _serve_alive(run_id, root)
        if alive is False:
            errors.append("mlflow serve pid is dead — re-run init (do not --force per hook)")
        elif alive is None:
            errors.append("mlflow_serve.pid missing — serve daemon not running")
    return errors


def required_agents(stage: str, run_id: str, root: Path | None = None) -> list[str]:
    key = (stage or "").strip().lower()
    agents = list(STAGE_AGENTS.get(key, []))
    if "convert" in agents and is_table_only(run_id, root):
        return [a for a in agents if a != "convert"]
    return agents


def check_stage(
    run_id: str,
    stage: str,
    *,
    root: Path | None = None,
    require_mlflow: bool | None = None,
) -> list[str]:
    """Return error strings. Empty list = watchable."""
    root = root or ROOT
    errors: list[str] = []
    rows = load_hook_events(run_id, root)
    agents = required_agents(stage, run_id, root)
    for agent in agents:
        starts = hook_starts_for(agent, rows)
        if not starts:
            errors.append(
                f"no hook subagentStart for agent={agent} "
                f"(dual_write start/completed is not enough) — launch edw-{agent}"
            )
            continue
        if agent == "convert":
            ids = wave_item_ids(run_id, root)
            if ids:
                blobs = [_blob(s) for s in starts]
                mentioned = any(iid in b for b in blobs for iid in ids)
                if mentioned:
                    missing = [iid for iid in ids if not any(iid in b for b in blobs)]
                    if missing:
                        errors.append(
                            "convert_wave item_id(s) missing subagentStart: "
                            + ",".join(missing)
                            + " — launch edw-convert per item"
                        )
    strict = is_strict(run_id, root)
    if require_mlflow is None:
        require_mlflow = strict
    if require_mlflow:
        stg = (stage or "").strip().lower()
        require_serve = stg not in {"gate", "done"}
        errors.extend(check_mlflow(run_id, root, require_serve=require_serve))
    return errors


def format_errors(stage: str, errors: list[str]) -> str:
    lines = [f"[assert_watchable] FAIL stage={stage}"]
    lines.extend(f"  - {e}" for e in errors)
    lines.append("Stop. Re-launch the missing edw-* Task so hooks fire. Do not dual_write-and-continue.")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--stage", required=True)
    ap.add_argument(
        "--skip-mlflow",
        action="store_true",
        help="Do not require mlflow_context / serve (unit tests)",
    )
    args = ap.parse_args()
    require_mlflow = False if args.skip_mlflow else None
    errors = check_stage(args.run_id, args.stage, require_mlflow=require_mlflow)
    if not errors:
        print(f"[assert_watchable] OK stage={args.stage} run_id={args.run_id}")
        return 0
    print(format_errors(args.stage, errors), file=sys.stderr)
    if is_strict(args.run_id):
        return 1
    print("[assert_watchable] WARN not strict (Track B) — continuing", file=sys.stderr)
    return 0


def fail_if_unwatchable(
    run_id: str,
    stage: str,
    *,
    root: Path | None = None,
    require_mlflow: bool | None = None,
) -> list[str]:
    """Return errors that should stop the caller (strict only). Non-strict prints WARN."""
    root = root or ROOT
    errors = check_stage(run_id, stage, root=root, require_mlflow=require_mlflow)
    if not errors:
        return []
    if is_strict(run_id, root):
        print(format_errors(stage, errors), file=sys.stderr)
        return errors
    for err in errors:
        print(f"[assert_watchable] WARN stage={stage} {err}", file=sys.stderr)
    return []


if __name__ == "__main__":
    raise SystemExit(main())
