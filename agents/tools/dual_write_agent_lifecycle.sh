#!/usr/bin/env bash
# dual_write_agent_lifecycle.sh — UC + MLflow lifecycle when Cursor hooks cannot fire.
#
# Use ONLY when Assess/Convert/Test/Gate cannot run as Cursor edw-* subagents.
# Preferred path: launch edw-assess / edw-convert / edw-test / edw-gate so
# .cursor/hooks/log_event.sh dual-writes automatically.
#
# Usage:
#   ./agents/tools/dual_write_agent_lifecycle.sh \
#     --run-id UUID --agent convert --phase start --item-id item-001 --detail '...'
#   ./agents/tools/dual_write_agent_lifecycle.sh \
#     --run-id UUID --agent convert --phase stop --item-id item-001 --detail 'ok' --status OK
#
# For parallel Convert, always pass --item-id (or --worker-id) so MLflow span keys do not collide.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

RUN_ID=""
AGENT=""
PHASE=""
DETAIL=""
STATUS="OK"
ITEM_ID=""
WORKER_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --detail) DETAIL="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --item-id) ITEM_ID="$2"; shift 2 ;;
    --worker-id) WORKER_ID="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,20p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

: "${RUN_ID:?--run-id required}"
: "${AGENT:?--agent required}"
: "${PHASE:?--phase required (start|stop)}"

case "$AGENT" in
  assess|convert|test|gate|coordinator|demo-guide|start) ;;
  *) echo "[dual_write] WARN: unusual agent label '${AGENT}'" >&2 ;;
esac

case "$PHASE" in
  start|stop) ;;
  *) echo "[dual_write] ERROR: --phase must be start or stop" >&2; exit 1 ;;
esac

WORKER="${ITEM_ID:-${WORKER_ID:-}}"
if [ -z "$WORKER" ]; then
  WORKER="$(date +%s%N)"
  if [ "$AGENT" = "convert" ]; then
    echo "[dual_write] WARN: convert without --item-id; using timestamp worker=${WORKER}" >&2
  fi
fi

RECORD="${REPO_ROOT}/agents/tools/record_agent_event.sh"
OBSERVE="${REPO_ROOT}/agents/tools/mlflow_observe.py"
FLUSH="${REPO_ROOT}/.cursor/hooks/_flush_events.sh"
PY="$("${REPO_ROOT}/agents/tools/resolve_python.sh" 2>/dev/null || command -v python3 || true)"
KEY="subagent:${AGENT}:${WORKER}"

EVENT="$PHASE"
if [ "$PHASE" = "stop" ]; then
  EVENT="completed"
  case "${STATUS}" in
    ERROR|error|failed|fail|1) EVENT="failed" ;;
  esac
fi

DETAIL_ARGS=()
[ -n "$DETAIL" ] && DETAIL_ARGS=(--detail "$DETAIL")

"$RECORD" --run-id "$RUN_ID" --agent "$AGENT" --event "$EVENT" "${DETAIL_ARGS[@]}"

HANDOFF_FROM="coordinator"
HANDOFF_TO="$AGENT"
HANDOFF_ACTION="$PHASE"
HANDOFF_OUTCOME="ok"
if [ "$PHASE" = "stop" ]; then
  HANDOFF_FROM="$AGENT"
  HANDOFF_TO="coordinator"
  case "${STATUS}" in
    ERROR|error|failed|fail|1) HANDOFF_OUTCOME="fail" ;;
  esac
  case "${DETAIL}" in
    *blocked*) HANDOFF_OUTCOME="blocked" ;;
  esac
fi
if [ -n "${PY:-}" ]; then
  "$PY" "${REPO_ROOT}/agents/tools/edw_handoff.py" \
    --run-id "$RUN_ID" \
    --from "$HANDOFF_FROM" \
    --to "$HANDOFF_TO" \
    --item-id "${ITEM_ID}" \
    --action "$HANDOFF_ACTION" \
    --outcome "$HANDOFF_OUTCOME" || true
fi

if [ -n "${PY:-}" ] && [ -f "$OBSERVE" ]; then
  SPAN_NAME="agent.${AGENT}"
  if [ "$AGENT" = "convert" ] && [ -n "${ITEM_ID:-}" ]; then
    SPAN_NAME="agent.convert.${ITEM_ID}"
  fi
  if [ "$PHASE" = "start" ]; then
    if ! "$PY" "$OBSERVE" span-start \
      --run-id "$RUN_ID" --key "$KEY" --name "$SPAN_NAME" \
      --kind agent --agent "$AGENT" --detail "$DETAIL"; then
      echo "[dual_write] MLflow span-start failed (see stderr)" >&2
    fi
  else
    ML_STATUS="OK"
    case "${STATUS}" in
      ERROR|error|failed|fail|1) ML_STATUS="ERROR" ;;
    esac
    case "${DETAIL}" in
      *blocked*) ML_STATUS="OK" ;;
    esac
    if ! "$PY" "$OBSERVE" span-end \
      --run-id "$RUN_ID" --key "$KEY" --detail "$DETAIL" --status "$ML_STATUS"; then
      echo "[dual_write] MLflow span-end failed (see stderr)" >&2
    fi
  fi
fi

if [ -x "$FLUSH" ]; then
  "$FLUSH" "$RUN_ID" >/dev/null 2>&1 || true
fi

echo "[dual_write] agent=${AGENT} phase=${PHASE} run_id=${RUN_ID} worker=${WORKER} event=${EVENT}"
