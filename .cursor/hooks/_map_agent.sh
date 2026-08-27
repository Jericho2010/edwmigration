#!/usr/bin/env bash
# Map Cursor hook payload -> agent label for ops.agent_events.
# Match subagent_type FIRST so "inventory" in a coordinator blob cannot steal assess.
set -euo pipefail
PAYLOAD="${1:-"{}"}"
python3 - "$PAYLOAD" <<'PY'
import json, sys
raw = sys.argv[1] if len(sys.argv) > 1 else "{}"
try:
    o = json.loads(raw)
except Exception:
    o = {}

TYPE_MAP = {
    "edw-assess": "assess",
    "edw-convert": "convert",
    "edw-test": "test",
    "edw-gate": "gate",
    "edw-coordinator": "coordinator",
    "edw-demo-guide": "demo-guide",
    "edw-start": "start",
    "assess": "assess",
    "convert": "convert",
    "test": "test",
    "gate": "gate",
    "coordinator": "coordinator",
    "demo-guide": "demo-guide",
    "start": "start",
}

st = str(o.get("subagent_type") or "").strip().lower()
if st in TYPE_MAP:
    print(TYPE_MAP[st])
    raise SystemExit(0)

blob = " ".join([
    str(o.get("agent") or ""),
    str(o.get("task") or ""),
    str(o.get("description") or ""),
    str(o.get("prompt") or ""),
    str(o.get("subagent_name") or ""),
    str(o.get("name") or ""),
]).lower()

def hit(*needles):
    return any(n in blob for n in needles)

if hit("edw-assess"):
    print("assess")
elif hit("edw-convert"):
    print("convert")
elif hit("edw-test"):
    print("test")
elif hit("edw-gate"):
    print("gate")
elif hit("edw-coordinator", "coordinator"):
    print("coordinator")
elif hit("edw-demo-guide", "demo-guide", "demo_guide"):
    print("demo-guide")
elif hit("assess") and not hit("coordinator"):
    print("assess")
elif hit("convert") and not hit("coordinator"):
    print("convert")
else:
    t = o.get("agent")
    print(t if t else "coordinator")
PY
