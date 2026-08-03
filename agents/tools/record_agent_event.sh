#!/usr/bin/env bash
# Insert one row into ${DATABRICKS_CATALOG}.ops.agent_events.
# Usage:
#   ./agents/tools/record_agent_event.sh --run-id UUID --agent convert \
#     --event skipped --detail 'no backlog (routines skipped)'
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    key="${line%%=*}"
    val="${line#*=}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    [ -n "$key" ] || continue
    if [ -z "${!key+x}" ]; then
      export "$key=$val"
    fi
  done < "${REPO_ROOT}/.env"
fi

: "${DATABRICKS_CATALOG:=edw_migration}"

RUN_ID=""
AGENT=""
EVENT=""
TOOL=""
DETAIL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --agent) AGENT="$2"; shift 2 ;;
    --event) EVENT="$2"; shift 2 ;;
    --tool) TOOL="$2"; shift 2 ;;
    --detail) DETAIL="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

: "${RUN_ID:?--run-id required}"
: "${AGENT:?--agent required}"
: "${EVENT:?--event required}"

# Escape single quotes for SQL literals
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

TOOL_SQL="NULL"
[ -n "$TOOL" ] && TOOL_SQL="'$(esc "$TOOL")'"
DETAIL_SQL="NULL"
[ -n "$DETAIL" ] && DETAIL_SQL="'$(esc "$DETAIL")'"

SQL="INSERT INTO ${DATABRICKS_CATALOG}.ops.agent_events
  (run_id, agent, event, tool, detail, ts)
VALUES
  ('$(esc "$RUN_ID")', '$(esc "$AGENT")', '$(esc "$EVENT")', ${TOOL_SQL}, ${DETAIL_SQL}, current_timestamp());
SELECT 'agent_event_ok' AS check_name, '${AGENT}' AS agent, '${EVENT}' AS event;"

"${REPO_ROOT}/agents/tools/run_sql.sh" --sql "$SQL"
echo "[record_agent_event] ${AGENT}/${EVENT} run_id=${RUN_ID}"
