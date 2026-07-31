#!/usr/bin/env bash
# Export reconcile fixtures from WideWorldImportersDW. Two flavors:
#
#   Get* procs (return result sets, take @LastCutoff / @NewCutoff):
#     The fixture is the proc's result set as CSV.
#
#   Migrate* procs (INSERT/UPDATE into Dimension tables, no result set):
#     The fixture is the target Dimension table state AFTER executing the proc.
#     WARNING: Migrate* procs mutate the database. Re-import the bacpac to get
#     a clean baseline before re-running this script.
#
# Fixtures are committed to legacy/fixtures/*.csv with stable column ordering.
#
# Usage:
#   ./export_fixtures.sh
# Relies on env vars: AZ_SQL_SERVER, AZ_SQL_ADMIN, AZ_SQL_PASSWORD, AZ_SQL_DB
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${AZ_SQL_SERVER:?AZ_SQL_SERVER must be set}"
: "${AZ_SQL_ADMIN:?AZ_SQL_ADMIN must be set}"
: "${AZ_SQL_PASSWORD:?AZ_SQL_PASSWORD must be set}"
: "${AZ_SQL_DB:=WideWorldImportersDW}"

SERVER_ARG="tcp:${AZ_SQL_SERVER}.database.windows.net,1433"
SQLCMD="sqlcmd -S ${SERVER_ARG} -U ${AZ_SQL_ADMIN} -P ${AZ_SQL_PASSWORD} -d ${AZ_SQL_DB} -C -l 60"

# A representative cutoff window. WWI's data ends mid-2016; pick a window that
# actually returns rows.
LAST_CUTOFF="20160101"
NEW_CUTOFF="20160301"

emit_csv() {
  local query="$1"
  local out="$2"
  echo "[export_fixtures] -> ${out}"
  $SQLCMD -h-1 -W -s "," -Q "$query" -o "$out"
}

echo "[export_fixtures] connecting to ${SERVER_ARG}/${AZ_SQL_DB} ..."

# ----- Get* procs: result sets as CSV --------------------------------------
emit_csv \
  "EXEC [Integration].[GetStockItemUpdates] @LastCutoff='${LAST_CUTOFF}', @NewCutoff='${NEW_CUTOFF}'" \
  "${SCRIPT_DIR}/get_stock_item_updates.csv"

emit_csv \
  "EXEC [Integration].[GetCustomerUpdates] @LastCutoff='${LAST_CUTOFF}', @NewCutoff='${NEW_CUTOFF}'" \
  "${SCRIPT_DIR}/get_customer_updates.csv"

emit_csv \
  "EXEC [Integration].[GetCityUpdates] @LastCutoff='${LAST_CUTOFF}', @NewCutoff='${NEW_CUTOFF}'" \
  "${SCRIPT_DIR}/get_city_updates.csv"

# ----- Migrate* procs: target-table state after execution ------------------
# Run the proc, then SELECT the resulting Dimension table.
# NOTE: this mutates the DB. Re-import the bacpac for a clean re-run.

echo "[export_fixtures] running Integration.MigrateStagedStockItemData (mutates DB) ..."
$SQLCMD -Q "EXEC [Integration].[MigrateStagedStockItemData]" >/dev/null
emit_csv \
  "SELECT * FROM [Dimension].[Stock Item] ORDER BY [WWI Stock Item ID]" \
  "${SCRIPT_DIR}/dim_stock_item_after_migrate.csv"

echo "[export_fixtures] running Integration.MigrateStagedCustomerData (mutates DB) ..."
$SQLCMD -Q "EXEC [Integration].[MigrateStagedCustomerData]" >/dev/null
emit_csv \
  "SELECT * FROM [Dimension].[Customer] ORDER BY [WWI Customer ID]" \
  "${SCRIPT_DIR}/dim_customer_after_migrate.csv"

# ----- Reference snapshots for reconcile (row counts, full table state) ----
emit_csv \
  "SELECT COUNT(*) AS row_count FROM [Fact].[Sale]" \
  "${SCRIPT_DIR}/fact_sale_count.csv"

emit_csv \
  "SELECT TOP 1000 * FROM [Fact].[Sale] ORDER BY [Sale Key]" \
  "${SCRIPT_DIR}/fact_sale_sample.csv"

emit_csv \
  "SELECT COUNT(*) AS row_count FROM [Dimension].[City]" \
  "${SCRIPT_DIR}/dim_city_count.csv"

emit_csv \
  "SELECT * FROM [Dimension].[City] ORDER BY [WWI City ID]" \
  "${SCRIPT_DIR}/dim_city_snapshot.csv"

echo "[export_fixtures] done. Files in ${SCRIPT_DIR}/"
echo "[export_fixtures] WARNING: the database has been mutated by the Migrate* procs."
echo "[export_fixtures] Re-import the bacpac (legacy/wideworldimportersdw/import_azure_sql.sh)"
echo "[export_fixtures] before re-running this script for a clean baseline."
