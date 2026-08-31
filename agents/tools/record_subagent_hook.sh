#!/usr/bin/env bash
# record_subagent_hook.sh — launch-time companion when Cursor omits subagentStart.
#
# Call ONLY in the same turn the parent launches a typed edw-* Task
# (edw-assess / edw-convert / edw-test / edw-gate). Writes the same
# events.buf.jsonl + spans.buf.jsonl shape as .cursor/hooks/log_event.sh.
# Not a persist-time fake. Not a substitute for launch_convert_wave.sh.
#
# Usage:
#   ./agents/tools/record_subagent_hook.sh --agent assess --event start
#   ./agents/tools/record_subagent_hook.sh --agent convert --event start --item-id item-001
#   ./agents/tools/record_subagent_hook.sh --agent assess --event stop
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

RUN_ID=""
AGENT=""
PHASE=""
ITEM_ID=""
DETAIL=""
STATUS="OK"
SKIP_FLUSH=0
ROOT_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --event) PHASE="$2"; shift 2 ;;
    --item-id) ITEM_ID="$2"; shift 2 ;;
    --detail) DETAIL="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --skip-flush) SKIP_FLUSH=1; shift ;;
    --root) ROOT_OVERRIDE="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,16p' "$0"
      exit 0
      ;;
    *) echo "[record_subagent_hook] Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$ROOT_OVERRIDE" ]; then
  REPO_ROOT="$ROOT_OVERRIDE"
fi

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

if [ -z "$RUN_ID" ] && [ -f "${REPO_ROOT}/agents/out/CURRENT_RUN" ]; then
  RUN_ID="$(tr -d '[:space:]' < "${REPO_ROOT}/agents/out/CURRENT_RUN")"
fi

: "${RUN_ID:?--run-id required (or agents/out/CURRENT_RUN)}"
: "${AGENT:?--agent required (assess|convert|test|gate)}"
: "${PHASE:?--event required (start|stop)}"

case "$AGENT" in
  assess|convert|test|gate) ;;
  *) echo "[record_subagent_hook] ERROR: --agent must be assess|convert|test|gate" >&2; exit 1 ;;
esac

case "$PHASE" in
  start|stop|subagentStart|subagentStop) ;;
  *) echo "[record_subagent_hook] ERROR: --event must be start|stop" >&2; exit 1 ;;
esac

if [ "$PHASE" = "start" ] || [ "$PHASE" = "subagentStart" ]; then
  EVENT="subagentStart"
else
  EVENT="subagentStop"
fi

if [ "$AGENT" = "convert" ] && [ -z "$ITEM_ID" ]; then
  echo "[record_subagent_hook] ERROR: convert requires --item-id (assert_watchable matches wave ids in detail)" >&2
  exit 1
fi

if [ -z "$DETAIL" ]; then
  if [ -n "$ITEM_ID" ]; then
    DETAIL="edw-${AGENT} | ${ITEM_ID}"
  else
    DETAIL="edw-${AGENT}"
  fi
fi

# Match log_event.sh: prefer Cursor-like sub_id, keep convert keys unique per item.
SUB_ID="$AGENT"
if [ -n "$ITEM_ID" ]; then
  SUB_ID="${AGENT}:${ITEM_ID}"
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
BUF_DIR="${REPO_ROOT}/agents/out/${RUN_ID}"
mkdir -p "$BUF_DIR"
BUF_FILE="${BUF_DIR}/events.buf.jsonl"
SPAN_Q="${BUF_DIR}/spans.buf.jsonl"
# Prefer the real repo enqueue helper even when --root is a temp tree.
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENQUEUE="${SCRIPT_ROOT}/agents/tools/enqueue_span.py"

python3 "$ENQUEUE" "$BUF_FILE" "$(python3 -c "
import json, sys
print(json.dumps({
    'run_id': sys.argv[1], 'agent': sys.argv[2], 'event': sys.argv[3],
    'tool': sys.argv[4], 'detail': sys.argv[5], 'ts': sys.argv[6],
}))
" "$RUN_ID" "$AGENT" "$EVENT" "Task" "$DETAIL" "$TS")"

python3 - "$ENQUEUE" "$SPAN_Q" "$EVENT" "$AGENT" "$SUB_ID" "$DETAIL" "$STATUS" <<'PY'
import json, subprocess, sys

enqueue, span_q, event, agent, sub_id, detail, status = sys.argv[1:8]
records = []
if event == "subagentStart":
    records.append({
        "op": "span-start",
        "key": f"subagent:{sub_id or agent}",
        "name": f"agent.{agent}",
        "kind": "agent",
        "agent": agent,
        "detail": detail,
    })
elif event == "subagentStop":
    ml_status = "ERROR" if str(status).lower() in ("error", "failed", "fail", "1") else "OK"
    records.append({
        "op": "span-end",
        "key": f"subagent:{sub_id or agent}",
        "detail": detail,
        "status": ml_status,
    })
if records:
    payload = "\n".join(json.dumps(r, separators=(",", ":")) for r in records) + "\n"
    subprocess.run([sys.executable, enqueue, span_q], input=payload, text=True, check=False)
PY

# Flush only on stop so persist/assert_watchable can still read the start row.
# _flush_events.sh moves events.buf.jsonl aside; a start-time flush races persist.
if [ "$SKIP_FLUSH" -eq 0 ] && [ "$EVENT" = "subagentStop" ]; then
  FLUSH="${SCRIPT_ROOT}/.cursor/hooks/_flush_events.sh"
  if [ -x "$FLUSH" ] && [ "$REPO_ROOT" = "$SCRIPT_ROOT" ]; then
    nohup bash -c '
      HOOK_DIR="$1"; RUN_ID="$2"; LOCK="$3"
      if command -v flock >/dev/null 2>&1; then
        exec 9>"$LOCK"
        flock -n 9 || exit 0
      fi
      "${HOOK_DIR}/_flush_events.sh" "$RUN_ID"
    ' _ "${SCRIPT_ROOT}/.cursor/hooks" "$RUN_ID" "${BUF_DIR}/flush.lock" >/dev/null 2>&1 &
    disown $! 2>/dev/null || true
  fi
fi

echo "[record_subagent_hook] agent=${AGENT} event=${EVENT} run_id=${RUN_ID}${ITEM_ID:+ item_id=${ITEM_ID}}"
