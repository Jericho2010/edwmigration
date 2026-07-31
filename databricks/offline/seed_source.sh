#!/usr/bin/env bash
# seed_source.sh — offline source mode: seed edw_migration.source_fed from
# generated CSVs instead of Lakehouse Federation. No Azure required.
#
#   1. generate_seed.py → CSVs (deterministic, WWI column contract)
#   2. 00_offline_source_setup.sql → catalog/schemas/volume/typed tables
#   3. curl PUT CSVs to the ops.offline_seed volume (Files API)
#   4. COPY INTO each source_fed table (casts CSV text to the DDL types)
#
# Usage:
#   ./databricks/offline/seed_source.sh [--sales N] [--keep-dir DIR]
#
# Env: DATABRICKS_HOST / DATABRICKS_TOKEN / DATABRICKS_WAREHOUSE_ID
# (sourced from .env if present). Requires python3, jq, curl, databricks CLI,
# and agents/tools/run_sql.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUN_SQL="${REPO_ROOT}/agents/tools/run_sql.sh"

SALES=25000
KEEP_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sales) SALES="$2"; shift 2 ;;
    --keep-dir) KEEP_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

: "${DATABRICKS_HOST:?DATABRICKS_HOST must be set}"
: "${DATABRICKS_TOKEN:?DATABRICKS_TOKEN must be set}"

for tool in python3 curl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "[seed] $tool is required" >&2; exit 1; }
done
[ -x "$RUN_SQL" ] || { echo "[seed] ${RUN_SQL} missing" >&2; exit 1; }

if [ -n "$KEEP_DIR" ]; then
  SEED_DIR="$KEEP_DIR"
  mkdir -p "$SEED_DIR"
else
  SEED_DIR="$(mktemp -d)"
  trap 'rm -rf "$SEED_DIR"' EXIT
fi

TABLES="dim_city dim_customer dim_stock_item dim_date fact_sale fact_stockholding"

echo "[seed] generating CSVs (sales=${SALES}) ..."
python3 "${SCRIPT_DIR}/generate_seed.py" --out "$SEED_DIR" --sales "$SALES"

echo "[seed] creating catalog/schemas/volume/tables ..."
"$RUN_SQL" --file "${SCRIPT_DIR}/00_offline_source_setup.sql"

echo "[seed] uploading CSVs to /Volumes/edw_migration/ops/offline_seed ..."
for t in $TABLES; do
  status="$(curl -sS -o /dev/null -w '%{http_code}' \
    -X PUT \
    -H "Authorization: Bearer ${DATABRICKS_TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${SEED_DIR}/${t}.csv" \
    "${DATABRICKS_HOST%/}/api/2.0/fs/files/Volumes/edw_migration/ops/offline_seed/${t}.csv?overwrite=true")"
  if [ "$status" != "200" ] && [ "$status" != "204" ]; then
    echo "[seed] upload failed for ${t}.csv (HTTP ${status})" >&2
    exit 1
  fi
  echo "[seed]   ${t}.csv uploaded"
done

echo "[seed] loading source_fed tables (INSERT from read_files) ..."
"$RUN_SQL" --file "${SCRIPT_DIR}/01_offline_source_load.sql"

echo "[seed] verifying row counts ..."
"$RUN_SQL" --sql "
SELECT 'dim_city' AS t, COUNT(*) AS n FROM edw_migration.source_fed.dim_city
UNION ALL SELECT 'dim_customer', COUNT(*) FROM edw_migration.source_fed.dim_customer
UNION ALL SELECT 'dim_stock_item', COUNT(*) FROM edw_migration.source_fed.dim_stock_item
UNION ALL SELECT 'dim_date', COUNT(*) FROM edw_migration.source_fed.dim_date
UNION ALL SELECT 'fact_sale', COUNT(*) FROM edw_migration.source_fed.fact_sale
UNION ALL SELECT 'fact_stockholding', COUNT(*) FROM edw_migration.source_fed.fact_stockholding"

echo "[seed] done. Next: ./agents/tools/run_sql.sh --file databricks/uc/03_ops_and_views.sql"
echo "[seed] then:  databricks bundle deploy -t dev && databricks bundle run edw_migration_medallion -t dev"
