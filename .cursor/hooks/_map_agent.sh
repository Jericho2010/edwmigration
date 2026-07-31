#!/usr/bin/env bash
# Map Cursor hook payload -> agent label for ops.agent_events.
set -euo pipefail
PAYLOAD="${1:-"{}"}"
python3 - "$PAYLOAD" <<'PY'
import json, sys, re
raw = sys.argv[1] if len(sys.argv) > 1 else "{}"
try:
    o = json.loads(raw)
except Exception:
    o = {}
blob = " ".join([
    str(o.get("subagent_type") or ""),
    str(o.get("agent") or ""),
    str(o.get("task") or ""),
    str(o.get("description") or ""),
    str(o.get("prompt") or ""),
    str(o.get("subagent_name") or ""),
    str(o.get("name") or ""),
]).lower()

def hit(*needles):
    return any(n in blob for n in needles)

if hit("edw-assess", "assess", "inventory", "backlog"):
    print("assess")
elif hit("edw-convert", "convert", "t-sql", "spark sql"):
    print("convert")
elif hit("edw-test", "reconcile") and not hit("edw-gate"):
    print("test")
elif hit("edw-gate", "gate", "ship/no-ship", "manifest"):
    print("gate")
elif hit("edw-coordinator", "coordinator"):
    print("coordinator")
else:
    t = o.get("subagent_type") or o.get("agent")
    print(t if t else "coordinator")
PY
