#!/usr/bin/env python3
"""One handoff record for chat, Control Plane, Genie, and MLflow.

detail JSON:
  {"from","to","item_id","action","artifact","outcome"}

outcome: ok | blocked | fail
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]

HANDOFF_KEYS = ("from", "to", "item_id", "action", "artifact", "outcome")
OK_OUTCOMES = frozenset({"ok", "blocked"})
FAIL_OUTCOMES = frozenset({"fail", "failed", "error"})


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


def handoff_detail(
    *,
    from_agent: str,
    to_agent: str,
    item_id: str = "",
    action: str = "launch",
    artifact: str = "",
    outcome: str = "ok",
) -> dict[str, str]:
    oc = (outcome or "ok").strip().lower()
    if oc in FAIL_OUTCOMES:
        oc = "fail"
    elif oc not in {"ok", "blocked"}:
        oc = "ok"
    return {
        "from": str(from_agent or ""),
        "to": str(to_agent or ""),
        "item_id": str(item_id or ""),
        "action": str(action or "launch"),
        "artifact": str(artifact or ""),
        "outcome": oc,
    }


def format_detail(payload: dict[str, str]) -> str:
    return json.dumps(payload, separators=(",", ":"), ensure_ascii=True)


def parse_detail(raw: str | None) -> dict[str, Any] | None:
    if not raw or not str(raw).strip():
        return None
    text = str(raw).strip()
    try:
        doc = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(doc, dict):
        return None
    return doc


def mlflow_status_for_outcome(outcome: str) -> str:
    """ERROR only on fail. blocked is OK (helpers blocked + Gate pass)."""
    oc = (outcome or "ok").strip().lower()
    if oc in FAIL_OUTCOMES:
        return "ERROR"
    return "OK"


def format_arrow(payload: dict[str, Any]) -> str:
    src = payload.get("from") or "?"
    dst = payload.get("to") or "?"
    item = payload.get("item_id") or ""
    outcome = payload.get("outcome") or ""
    extra = f" ({item})" if item else ""
    oc = f" {outcome}" if outcome else ""
    return f"{src} → {dst}{extra}{oc}".strip()


def emit_handoff(
    run_id: str,
    *,
    from_agent: str,
    to_agent: str,
    item_id: str = "",
    action: str = "launch",
    artifact: str = "",
    outcome: str = "ok",
    skip_ops: bool = False,
) -> dict[str, str]:
    """Write UC event=handoff (agent=receiver) + MLflow attributes via record."""
    payload = handoff_detail(
        from_agent=from_agent,
        to_agent=to_agent,
        item_id=item_id,
        action=action,
        artifact=artifact,
        outcome=outcome,
    )
    detail = format_detail(payload)
    if skip_ops:
        return payload

    record = ROOT / "agents" / "tools" / "record_agent_event.sh"
    cmd = [
        str(record),
        "--run-id",
        run_id,
        "--agent",
        to_agent or from_agent or "coordinator",
        "--event",
        "handoff",
        "--detail",
        detail,
    ]
    proc = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr or proc.stdout or "[emit_handoff] record failed\n")
    return payload


def emit_handoff_quiet(run_id: str, **kwargs: Any) -> dict[str, str] | None:
    """emit_handoff that never raises (persist / merge callers)."""
    try:
        return emit_handoff(run_id, **kwargs)
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"[emit_handoff] {exc}\n")
        return None


def main() -> int:
    load_env()
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-id", required=True)
    ap.add_argument("--from", dest="from_agent", required=True)
    ap.add_argument("--to", dest="to_agent", required=True)
    ap.add_argument("--item-id", default="")
    ap.add_argument("--action", default="launch")
    ap.add_argument("--artifact", default="")
    ap.add_argument("--outcome", default="ok")
    ap.add_argument("--skip-ops", action="store_true")
    args = ap.parse_args()
    payload = emit_handoff(
        args.run_id,
        from_agent=args.from_agent,
        to_agent=args.to_agent,
        item_id=args.item_id,
        action=args.action,
        artifact=args.artifact,
        outcome=args.outcome,
        skip_ops=args.skip_ops,
    )
    print(format_detail(payload))
    print(format_arrow(payload))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
