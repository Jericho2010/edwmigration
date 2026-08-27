#!/usr/bin/env bash
# log_event.sh — buffer Cursor lifecycle events -> ops.agent_events (via flush).
# Cursor payloads do not include run_id; see _resolve_run_id.sh / CURRENT_RUN.
set -euo pipefail

# Default 1 so Control Plane timeline updates during parent-shell demos
# (no subagentStop). Override with AGENT_EVENT_FLUSH_THRESHOLD if needed.
FLUSH_THRESHOLD="${AGENT_EVENT_FLUSH_THRESHOLD:-1}"
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
sub_id = o.get("subagent_id") or o.get("subagent_type") or o.get("agent") or ""
exit_code = o.get("exit_code")
if exit_code is None:
    exit_code = o.get("status") or ""
print(f"EVENT={shlex.quote(str(event)[:80])}")
print(f"TOOL={shlex.quote(str(tool)[:200])}")
print(f"DETAIL={shlex.quote(str(detail)[:500])}")
print(f"SUB_ID={shlex.quote(str(sub_id)[:120])}")
print(f"EXIT_CODE={shlex.quote(str(exit_code)[:40])}")
PY
)"

# SoD: coordinator/demo-guide must not write silver/gold; convert needs wave lock.
if [ "$EVENT" = "afterFileEdit" ] && [ "$RUN_ID" != "unknown" ]; then
  FILE_PATH="$(python3 -c 'import json,sys; o=json.loads(sys.argv[1] or "{}"); print(o.get("file_path") or o.get("path") or "")' "$PAYLOAD" 2>/dev/null || true)"
  if [ -n "${FILE_PATH:-}" ]; then
    python3 "${REPO_ROOT}/agents/tools/assert_squad_sod.py" \
      --run-id "$RUN_ID" --agent "$AGENT" --file "$FILE_PATH" >/dev/null 2>&1 || true
  fi
fi

BUF_DIR="${REPO_ROOT}/agents/out/${RUN_ID}"
mkdir -p "$BUF_DIR"
BUF_FILE="${BUF_DIR}/events.buf.jsonl"
SPAN_Q="${BUF_DIR}/spans.buf.jsonl"
ENQUEUE="${REPO_ROOT}/agents/tools/enqueue_span.py"
TS="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"

python3 "$ENQUEUE" "$BUF_FILE" "$(python3 -c "
import json, sys
print(json.dumps({
    'run_id': sys.argv[1], 'agent': sys.argv[2], 'event': sys.argv[3],
    'tool': sys.argv[4], 'detail': sys.argv[5], 'ts': sys.argv[6],
}))
" "$RUN_ID" "$AGENT" "$EVENT" "$TOOL" "$DETAIL" "$TS")"

# Dual-write MLflow spans via locked JSONL (serve daemon owns the trace).
if [ "$RUN_ID" != "unknown" ] && [ -f "$ENQUEUE" ]; then
  python3 - "$ENQUEUE" "$SPAN_Q" "$EVENT" "$AGENT" "$SUB_ID" "$DETAIL" "$TOOL" "$EXIT_CODE" <<'PY' || true
import json, subprocess, sys, time

enqueue, span_q, event, agent, sub_id, detail, tool, exit_code = sys.argv[1:9]
records = []
now = str(int(time.time() * 1e9))

def rec(**kwargs):
    records.append(kwargs)

if event == "subagentStart":
    rec(op="span-start", key=f"subagent:{sub_id or agent}", name=f"agent.{agent}",
        kind="agent", agent=agent, detail=detail)
elif event == "subagentStop":
    status = "ERROR" if str(exit_code).lower() in ("error", "failed", "fail", "1") else "OK"
    rec(op="span-end", key=f"subagent:{sub_id or agent}", detail=detail, status=status)
elif event == "afterShellExecution":
    key = f"tool:shell:{now}"
    status = "OK" if str(exit_code) in ("0", "") else "ERROR"
    rec(op="span-start", key=key, name="tool.shell", kind="tool", detail=detail or tool)
    rec(op="span-end", key=key, detail=detail, status=status)
    rec(op="metric", key="shell_success" if status == "OK" else "shell_failure", value=1)
elif event == "afterMCPExecution":
    key = f"tool:mcp:{now}"
    rec(op="span-start", key=key, name="tool.mcp", kind="tool", detail=detail or tool)
    rec(op="span-end", key=key, detail=detail, status="OK")
elif event == "afterFileEdit":
    key = f"tool:file:{now}"
    rec(op="span-start", key=key, name="tool.file_edit", kind="tool", detail=detail)
    rec(op="span-end", key=key, detail=detail, status="OK")

if records:
    payload = "\n".join(json.dumps(r, separators=(",", ":")) for r in records) + "\n"
    subprocess.run([sys.executable, enqueue, span_q], input=payload, text=True, check=False)
PY
fi

COUNT="$(wc -l < "$BUF_FILE" | tr -d ' ')"
if [ "$COUNT" -ge "$FLUSH_THRESHOLD" ]; then
  # Do not block the 15s hook on warehouse INSERT. One flush at a time.
  nohup bash -c '
    HOOK_DIR="$1"; RUN_ID="$2"; LOCK="$3"
    if command -v flock >/dev/null 2>&1; then
      exec 9>"$LOCK"
      flock -n 9 || exit 0
    fi
    "${HOOK_DIR}/_flush_events.sh" "$RUN_ID"
  ' _ "$HOOK_DIR" "$RUN_ID" "${BUF_DIR}/flush.lock" >/dev/null 2>&1 &
  disown $! 2>/dev/null || true
fi

echo '{}'
exit 0
