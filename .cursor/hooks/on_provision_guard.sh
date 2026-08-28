#!/usr/bin/env bash
# Kick the agent if it announced Track A Provision URLs and then stopped
# without starting track_a_provision.sh / make provision-track-a.
#
# Usage (hooks.json):
#   .cursor/hooks/on_provision_guard.sh after-shell
#   .cursor/hooks/on_provision_guard.sh stop
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$("${HOOK_DIR}/_repo_root.sh")"
MODE="${1:-}"
STAMP="${EDW_PROVISION_GUARD_STAMP:-${REPO_ROOT}/agents/out/.provision_required}"
MAX_AGE_SEC="${EDW_PROVISION_GUARD_MAX_AGE_SEC:-1800}"
KICK='Do not wait. You announced Provision URLs but did not start setup. Next Shell call this turn: DATABRICKS_CATALOG=<catalog> ./agents/tools/track_a_provision.sh'

PAYLOAD="$(cat || true)"
if [ -z "$PAYLOAD" ]; then
  PAYLOAD='{}'
fi

python3 - "$MODE" "$STAMP" "$MAX_AGE_SEC" "$KICK" "$PAYLOAD" <<'PY'
import json, os, sys, time
from pathlib import Path

mode, stamp_s, max_age_s, kick, raw = sys.argv[1:6]
stamp = Path(stamp_s)
max_age = int(max_age_s)
try:
    payload = json.loads(raw) if raw else {}
except Exception:
    payload = {}

def cmd_of(o: dict) -> str:
    parts = [
        o.get("command"),
        o.get("tool"),
        o.get("tool_name"),
    ]
    ti = o.get("tool_input")
    if isinstance(ti, dict):
        parts.append(ti.get("command"))
    elif isinstance(ti, str):
        parts.append(ti)
    return " ".join(str(p) for p in parts if p).lower()

def is_provision(cmd: str) -> bool:
    return any(
        s in cmd
        for s in (
            "track_a_provision.sh",
            "provision-track-a",
            "make bootstrap",
            "make setup",
        )
    )

def is_standalone_announce(cmd: str) -> bool:
    if is_provision(cmd):
        return False
    if "announce_observability.sh" not in cmd:
        return False
    return "--stage provision" in cmd or "stage provision" in cmd

def provision_running() -> bool:
    flag = os.environ.get("EDW_PROVISION_GUARD_RUNNING")
    if flag == "1":
        return True
    if flag == "0":
        return False
    try:
        import subprocess
        r = subprocess.run(
            ["pgrep", "-f", r"track_a_provision\.sh|provision-track-a"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return r.returncode == 0
    except Exception:
        return False

def stamp_fresh() -> bool:
    if not stamp.is_file():
        return False
    try:
        age = time.time() - stamp.stat().st_mtime
    except OSError:
        return False
    return 0 <= age <= max_age

event = str(payload.get("hook_event_name") or payload.get("event") or mode or "").lower()
if not mode:
    if "stop" in event and "subagent" not in event:
        mode = "stop"
    else:
        mode = "after-shell"

if mode == "after-shell":
    cmd = cmd_of(payload)
    stamp.parent.mkdir(parents=True, exist_ok=True)
    if is_provision(cmd):
        try:
            stamp.unlink()
        except OSError:
            pass
        print("{}")
    elif is_standalone_announce(cmd):
        stamp.write_text("provision_required\n")
        print(json.dumps({"additional_context": kick}))
    else:
        print("{}")
    raise SystemExit(0)

if mode == "stop":
    if stamp_fresh() and not provision_running():
        print(json.dumps({"followup_message": kick}))
    else:
        print("{}")
    raise SystemExit(0)

print("{}")
PY
exit 0
