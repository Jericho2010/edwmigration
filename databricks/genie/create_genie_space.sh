#!/usr/bin/env bash
# Create/update the EDW Migration Copilot Genie space with dynamic table_identifiers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG="${SCRIPT_DIR}/space_config.json"
RUN_SQL="${REPO_ROOT}/agents/tools/run_sql.sh"

STRICT=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    -h|--help)
      echo "Usage: $0 [--strict]"
      echo "  --strict  fail on create/PATCH errors (use after Land)."
      echo "  Default is WARN so make setup is not blocked."
      exit 0
      ;;
  esac
done
if [ "${GENIE_STRICT:-}" = "1" ]; then
  STRICT=1
fi

fail_or_warn() {
  local msg="$1"
  if [ "$STRICT" = "1" ]; then
    echo "[genie] ERROR: ${msg}" >&2
    echo "[genie] Re-run make genie GENIE_STRICT=1 after land; do not keep a stale space silently." >&2
    exit 1
  fi
  echo "[genie] WARN: ${msg} (continuing; re-run make genie GENIE_STRICT=1 after Land)" >&2
}

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi
# shellcheck disable=SC1091
. "${REPO_ROOT}/agents/tools/apply_databricks_cli_auth.sh"

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

# API export proto: version/config/data_sources only; sample_question.id must be
# lowercase 32-hex (no hyphens). Top-level "instructions" is rejected as VALUE_STRING.
SERIALIZED="$(jq -c --argjson tables "$TABLES_JSON" '
  .serialized_space
  | del(.instructions)
  | .data_sources.tables = ($tables | sort | map({identifier: .}))
' "$CONFIG")"

SPACE_ID="$(
  databricks api get /api/2.0/genie/spaces \
    | jq -r --arg t "$TITLE" '.spaces // [] | map(select(.title == $t)) | .[0].space_id // empty'
)"

if [ -n "$SPACE_ID" ]; then
  echo "[genie] updating existing space ${SPACE_ID} ('${TITLE}') ..."
  if ! databricks genie update-space "$SPACE_ID" \
      --serialized-space "$SERIALIZED" \
      --title "$TITLE" \
      --description "$DESCRIPTION" \
      --warehouse-id "$DATABRICKS_WAREHOUSE_ID" >/dev/null; then
    fail_or_warn "update failed for space ${SPACE_ID}"
  fi
else
  echo "[genie] creating space '${TITLE}' ..."
  if ! CREATE_OUT="$(databricks genie create-space "$DATABRICKS_WAREHOUSE_ID" "$SERIALIZED" \
      --title "$TITLE" \
      --description "$DESCRIPTION" -o json)"; then
    fail_or_warn "create failed"
    CREATE_OUT=""
  fi
  SPACE_ID="$(printf '%s' "$CREATE_OUT" | jq -r '.space_id // .id // empty')"
fi

if [ -z "$SPACE_ID" ]; then
  fail_or_warn "no space_id returned"
  exit 0
fi

echo "[genie] done. Open: ${DATABRICKS_HOST%/}/genie/rooms/${SPACE_ID}"
