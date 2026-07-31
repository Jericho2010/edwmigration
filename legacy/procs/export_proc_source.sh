#!/usr/bin/env bash
# Export the T-SQL source of every stored procedure in the [Integration] schema
# (and a small set of helper procs in [Configuration] / [Application]) from the
# WideWorldImportersDW Azure SQL database, one .sql file per proc.
#
# These files are the migration teaching surface: the Convert agent reads each
# proc's source and emits an equivalent Databricks notebook.
#
# Usage:
#   ./export_proc_source.sh
# Relies on env vars: AZ_SQL_SERVER, AZ_SQL_ADMIN, AZ_SQL_PASSWORD, AZ_SQL_DB
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${AZ_SQL_SERVER:?AZ_SQL_SERVER must be set}"
: "${AZ_SQL_ADMIN:?AZ_SQL_ADMIN must be set}"
: "${AZ_SQL_PASSWORD:?AZ_SQL_PASSWORD must be set}"
: "${AZ_SQL_DB:=WideWorldImportersDW}"

SERVER_ARG="tcp:${AZ_SQL_SERVER}.database.windows.net,1433"
SQLCMD="sqlcmd -S ${SERVER_ARG} -U ${AZ_SQL_ADMIN} -P ${AZ_SQL_PASSWORD} -d ${AZ_SQL_DB} -C -l 60"

echo "[export_proc_source] connecting to ${SERVER_ARG}/${AZ_SQL_DB} ..."

# Pull (schema_name, proc_name, definition) for the schemas we care about.
# Use -y0 to avoid truncating long definitions (sqlcmd truncates at 1MB by
# default; -y0 disables the column-width limit). Wrap definition in a sentinel
# so we can split the TSV reliably even if it contains tabs/newlines.
QUERY=$(cat <<'SQL'
SET NOCOUNT ON;
SELECT
  s.name AS schema_name,
  o.name AS proc_name,
  m.definition AS definition
FROM sys.sql_modules m
JOIN sys.objects o ON m.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'P'
  AND s.name IN ('Integration', 'Configuration', 'Application')
ORDER BY s.name, o.name;
SQL
)

RAW_TSV="$($SQLCMD -h-1 -W -s $'\t' -Q "$QUERY" 2>/dev/null)"

if [ -z "$RAW_TSV" ]; then
  echo "[export_proc_source] ERROR: no rows returned. Check connectivity and proc schema." >&2
  exit 1
fi

# Parse line-by-line. Definitions may contain newlines, so we use a sentinel
# pattern: each row is "schema\tproc\t<definition-up-to-end-of-row>". sqlcmd -W
# trims trailing whitespace; the final column is the full definition.
COUNT=0
while IFS=$'\t' read -r SCHEMA_NAME PROC_NAME DEFINITION; do
  [ -z "${SCHEMA_NAME:-}" ] && continue
  OUT_FILE="${SCRIPT_DIR}/${SCHEMA_NAME}.${PROC_NAME}.sql"
  # Strip any leading/trailing whitespace from the definition
  printf '%s\n' "$DEFINITION" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' > "$OUT_FILE"
  echo "[export_proc_source] wrote ${SCHEMA_NAME}.${PROC_NAME}.sql ($(wc -l < "$OUT_FILE") lines)"
  COUNT=$((COUNT + 1))
done <<< "$RAW_TSV"

echo "[export_proc_source] exported ${COUNT} proc(s) to ${SCRIPT_DIR}/"
