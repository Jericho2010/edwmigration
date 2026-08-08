#!/usr/bin/env bash
# log_event.sh — buffer Cursor lifecycle events -> ops.agent_events (via flush).
# Cursor payloads do not include run_id; see _resolve_run_id.sh / CURRENT_RUN.
set -euo pipefail

FLUSH_THRESHOLD="${AGENT_EVENT_FLUSH_THRESHOLD:-10}"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$("${HOOK_DIR}/_repo_root.sh")"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

PAYLOAD="$(cat || true)"
if [ -z "$PAYLOAD" ]; then
  echo '{}'
  exit 0
fi

RUN_ID="$("${HOOK_DIR}/_resolve_run_id.sh" "$REPO_ROOT")"
AGENT="$("${HOOK_DIR}/_map_agent.sh" "$PAYLOAD")"

# Parse remaining fields with python3 (jq optional)
eval "$(python3 - "$PAYLOAD" <<'PY'
import json, sys, shlex
raw = sys.argv[1]
try:
    o = json.loads(raw)
except Exception:
    o = {}
event = o.get("hook_event_name") or o.get("event")
if not event:
    if o.get("status") is not None:
        event = "subagentStop"
    elif o.get("subagent_id") is not None:
        event = "subagentStart"
    elif o.get("file_path") is not None:
        event = "afterFileEdit"
    else:
        event = "lifecycle"
tool = o.get("tool_name") or o.get("tool") or o.get("command") or ""
parts = [o.get("task"), o.get("status"), o.get("file_path"), o.get("description")]
detail = " | ".join(str(p) for p in parts if p)
print(f"EVENT={shlex.quote(str(event)[:80])}")
print(f"TOOL={shlex.quote(str(tool)[:200])}")
print(f"DETAIL={shlex.quote(str(detail)[:500])}")
PY
)"

BUF_DIR="${REPO_ROOT}/agents/out/${RUN_ID}"
mkdir -p "$BUF_DIR"
BUF_FILE="${BUF_DIR}/events.buf.jsonl"
TS="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

python3 - "$BUF_FILE" "$RUN_ID" "$AGENT" "$EVENT" "$TOOL" "$DETAIL" "$TS" <<'PY'
import json, sys
path, run_id, agent, event, tool, detail, ts = sys.argv[1:]
with open(path, "a") as f:
    f.write(json.dumps({
        "run_id": run_id, "agent": agent, "event": event,
        "tool": tool, "detail": detail, "ts": ts,
    }) + "\n")
PY

COUNT="$(wc -l < "$BUF_FILE" | tr -d ' ')"
if [ "$COUNT" -ge "$FLUSH_THRESHOLD" ]; then
  "${HOOK_DIR}/_flush_events.sh" "$RUN_ID" || true
fi

echo '{}'
exit 0
