#!/usr/bin/env bash
# reset_databricks_sink.sh — Wipe managed UC sink + local run artifacts.
# Keeps Azure SQL, .env SOURCE_*, foreign catalog / connection, Genie/dashboard defs.
#
# Usage: ./agents/tools/reset_databricks_sink.sh
#        make reset-sink
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi
# shellcheck disable=SC1091
. "${REPO_ROOT}/agents/tools/apply_databricks_cli_auth.sh"

: "${DATABRICKS_CATALOG:?DATABRICKS_CATALOG must be set in .env}"
: "${DATABRICKS_HOST:?DATABRICKS_HOST must be set in .env}"
: "${DATABRICKS_WAREHOUSE_ID:?DATABRICKS_WAREHOUSE_ID must be set in .env}"

CATALOG="$DATABRICKS_CATALOG"

echo
echo "=== reset-sink (Databricks only) ==="
echo "  catalog=${CATALOG}"
echo "  KEEPS: Azure SQL, .env SOURCE_*, foreign catalog/connection, Genie/dashboard defs"
echo "  WIPES: ${CATALOG}.ops.* rows, bronze/silver/gold tables+views, agents/out/<run_id>"
echo

RUN_SQL="${REPO_ROOT}/agents/tools/run_sql.sh"

# Truncate / clear ops control tables (CREATE IF NOT EXISTS may leave them empty after first setup).
OPS_TABLES=(
  agent_events
  migration_inventory
  migration_backlog
  reconcile_results
  migration_manifest_current
  proc_conversion_map
  fixture_expectations
  load_control
)

OPS_SQL=""
for t in "${OPS_TABLES[@]}"; do
  OPS_SQL+="DELETE FROM ${CATALOG}.ops.${t};"$'\n'
done
OPS_SQL+="SELECT 'ops_cleared' AS check_name;"

echo "[reset-sink] clearing ops.* ..."
"$RUN_SQL" --sql "$OPS_SQL"

# Drop bronze/silver/gold managed tables AND views (views survive a
# table-only wipe and dangle against dropped base tables).
echo "[reset-sink] listing bronze/silver/gold tables and views ..."
LIST_OUT="$("$RUN_SQL" --sql "
SELECT table_schema, table_name, table_type
FROM ${CATALOG}.information_schema.tables
WHERE table_schema IN ('bronze','silver','gold')
  AND table_type IN ('MANAGED', 'BASE TABLE', 'VIEW', 'MATERIALIZED_VIEW')
ORDER BY table_schema, table_name;
" 2>/dev/null || true)"

DROP_SQL=""
DROP_COUNT=0
while IFS=$'\t' read -r schema name ttype; do
  [ -z "${schema:-}" ] && continue
  [ "$schema" = "table_schema" ] && continue
  case "$schema" in
    bronze|silver|gold) ;;
    *) continue ;;
  esac
  # identifier safety: only simple names
  if ! printf '%s' "$schema.$name" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$'; then
    echo "[reset-sink] WARN: skip unsafe identifier ${schema}.${name}" >&2
    continue
  fi
  case "${ttype:-}" in
    VIEW|MATERIALIZED_VIEW)
      DROP_SQL+="DROP VIEW IF EXISTS ${CATALOG}.${schema}.${name};"$'\n'
      ;;
    *)
      DROP_SQL+="DROP TABLE IF EXISTS ${CATALOG}.${schema}.${name};"$'\n'
      ;;
  esac
  DROP_COUNT=$((DROP_COUNT + 1))
done <<<"$LIST_OUT"

if [ "$DROP_COUNT" -gt 0 ]; then
  echo "[reset-sink] dropping ${DROP_COUNT} table/view(s) ..."
  DROP_SQL+="SELECT 'medallion_dropped' AS check_name, ${DROP_COUNT} AS n;"
  "$RUN_SQL" --sql "$DROP_SQL"
else
  echo "[reset-sink] no bronze/silver/gold tables or views to drop"
fi

# Local run artifacts
OUT_DIR="${REPO_ROOT}/agents/out"
if [ -d "$OUT_DIR" ]; then
  echo "[reset-sink] clearing agents/out run dirs ..."
  find "$OUT_DIR" -mindepth 1 -maxdepth 1 ! -name '.gitkeep' -exec rm -rf {} +
fi

echo
echo "[reset-sink] done. Expected empty Control Plane until Discover/load_inventory."
echo
"${REPO_ROOT}/agents/tools/print_observability_urls.sh" || true
echo "[reset-sink] Azure untouched. Next: mint a run_id and Discover."
