#!/usr/bin/env bash
# Create/update the EDW Migration Copilot Genie space with dynamic table_identifiers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG="${SCRIPT_DIR}/space_config.json"
RUN_SQL="${REPO_ROOT}/agents/tools/run_sql.sh"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

: "${DATABRICKS_WAREHOUSE_ID:?DATABRICKS_WAREHOUSE_ID must be set}"
: "${DATABRICKS_CATALOG:=edw_migration}"
: "${DATABRICKS_HOST:?DATABRICKS_HOST must be set}"

for tool in jq databricks python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "[genie] $tool is required" >&2; exit 1; }
done

TITLE="$(jq -r '.title' "$CONFIG")"
DESCRIPTION="$(jq -r '.description' "$CONFIG")"

TABLES_FILE="$(mktemp)"
{
  echo "${DATABRICKS_CATALOG}.ops.agent_events"
  echo "${DATABRICKS_CATALOG}.ops.migration_inventory"
  echo "${DATABRICKS_CATALOG}.ops.migration_backlog"
  echo "${DATABRICKS_CATALOG}.ops.proc_conversion_map"
  echo "${DATABRICKS_CATALOG}.ops.reconcile_results"
  echo "${DATABRICKS_CATALOG}.ops.migration_manifest_current"
  echo "${DATABRICKS_CATALOG}.ops.load_control"
} >"$TABLES_FILE"

# Best-effort append gold/silver tables (ignore failures before first land).
if SQL_OUT="$("$RUN_SQL" --sql "SELECT table_schema, table_name FROM ${DATABRICKS_CATALOG}.information_schema.tables WHERE table_schema IN ('gold','silver') AND table_type='BASE TABLE'" 2>/dev/null || true)"; then
  while IFS=$'\t' read -r schema name; do
    [ "$schema" = "table_schema" ] && continue
    [ -z "${schema:-}" ] && continue
    echo "${DATABRICKS_CATALOG}.${schema}.${name}" >>"$TABLES_FILE"
  done <<<"$SQL_OUT"
fi

TABLES_JSON="$(python3 - <<PY
import json
from pathlib import Path
rows = [ln.strip() for ln in Path("${TABLES_FILE}").read_text().splitlines() if ln.strip()]
# de-dupe preserve order
seen=set(); out=[]
for r in rows:
    if r not in seen:
        seen.add(r); out.append(r)
print(json.dumps(out))
PY
)"
rm -f "$TABLES_FILE"

SERIALIZED="$(jq -c --argjson tables "$TABLES_JSON" '
  .serialized_space
  | .data_sources.tables = ($tables | map({identifier: .}))
' "$CONFIG")"

SPACE_ID="$(
  databricks api get /api/2.0/genie/spaces \
    | jq -r --arg t "$TITLE" '.spaces // [] | map(select(.title == $t)) | .[0].space_id // empty'
)"

PAYLOAD="$(jq -n \
  --arg wid "$DATABRICKS_WAREHOUSE_ID" \
  --arg title "$TITLE" \
  --arg desc "$DESCRIPTION" \
  --argjson ser "$SERIALIZED" \
  '{warehouse_id: $wid, title: $title, description: $desc, serialized_space: ($ser | tostring)}')"

if [ -n "$SPACE_ID" ]; then
  echo "[genie] updating existing space ${SPACE_ID} ('${TITLE}') ..."
  databricks api patch "/api/2.0/genie/spaces/${SPACE_ID}" --json "$PAYLOAD" >/dev/null
else
  echo "[genie] creating space '${TITLE}' ..."
  SPACE_ID="$(databricks api post /api/2.0/genie/spaces --json "$PAYLOAD" | jq -r '.space_id // .id // empty')"
fi

if [ -z "$SPACE_ID" ]; then
  echo "[genie] ERROR: no space_id returned" >&2
  exit 1
fi

echo "[genie] done. Open: ${DATABRICKS_HOST%/}/genie/rooms/${SPACE_ID}"
