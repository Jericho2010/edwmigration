#!/usr/bin/env bash
# Export T-SQL procedure source from WideWorldImportersDW (or connected Azure SQL).
#
# Writes Schema.Proc.sql files into PROC_EXPORT_DIR only — never overwrites the
# vendored teaching copies in this directory (legacy/procs/Integration.*.sql).
#
# Usage:
#   PROC_EXPORT_DIR=/path/to/out ./export_proc_source.sh
#   # bootstrap default when unset:
#   ./export_proc_source.sh   # → legacy/procs/.export/ (gitignored)
#
# Relies on: AZ_SQL_SERVER, AZ_SQL_ADMIN, AZ_SQL_PASSWORD, AZ_SQL_DB
#
# Note: go-sqlcmd can split multi-line definitions across rows when selecting
# schema/proc/definition together — export one proc at a time instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${AZ_SQL_SERVER:?AZ_SQL_SERVER must be set}"
: "${AZ_SQL_ADMIN:?AZ_SQL_ADMIN must be set}"
: "${AZ_SQL_PASSWORD:?AZ_SQL_PASSWORD must be set}"
: "${AZ_SQL_DB:=WideWorldImportersDW}"

# Live dumps go to PROC_EXPORT_DIR (discover sets this to agents/out/<run_id>/procs).
# Default is a gitignored cache so bootstrap cannot dirty vendored Integration.*.sql.
PROC_EXPORT_DIR="${PROC_EXPORT_DIR:-${SCRIPT_DIR}/.export}"
mkdir -p "${PROC_EXPORT_DIR}"
PROC_EXPORT_DIR="$(cd "${PROC_EXPORT_DIR}" && pwd)"

if [ "${PROC_EXPORT_DIR}" = "${SCRIPT_DIR}" ]; then
  echo "[export_proc_source] ERROR: PROC_EXPORT_DIR must not be legacy/procs (vendored teaching set)." >&2
  echo "  Use agents/out/<run_id>/procs or legacy/procs/.export" >&2
  exit 1
fi

SERVER_ARG="tcp:${AZ_SQL_SERVER}.database.windows.net,1433"
SQLCMD=(sqlcmd -S "${SERVER_ARG}" -U "${AZ_SQL_ADMIN}" -P "${AZ_SQL_PASSWORD}" -d "${AZ_SQL_DB}" -C -l 60 -h -1 -W -y 0)

echo "[export_proc_source] connecting to ${SERVER_ARG}/${AZ_SQL_DB} ..."
echo "[export_proc_source] writing to ${PROC_EXPORT_DIR}"

LIST_QUERY=$(cat <<'SQL'
SET NOCOUNT ON;
SELECT s.name + N'.' + o.name
FROM sys.objects o
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'P'
  AND s.name IN ('Integration', 'Configuration', 'Application')
ORDER BY s.name, o.name;
SQL
)

mapfile -t PROC_NAMES < <("${SQLCMD[@]}" -Q "${LIST_QUERY}" | tr -d '\r' | sed '/^$/d')

if [ "${#PROC_NAMES[@]}" -eq 0 ]; then
  echo "[export_proc_source] ERROR: no rows returned. Check connectivity and proc schema." >&2
  exit 1
fi

# Clear prior dumps in the export dir only (never touch vendored files).
find "${PROC_EXPORT_DIR}" -maxdepth 1 -type f -name '*.sql' -delete 2>/dev/null || true

COUNT=0
for FULL in "${PROC_NAMES[@]}"; do
  FULL="$(printf '%s' "$FULL" | tr -d '[:space:]')"
  [ -n "$FULL" ] || continue
  SCHEMA_NAME="${FULL%%.*}"
  PROC_NAME="${FULL#*.}"
  if [ -z "$SCHEMA_NAME" ] || [ -z "$PROC_NAME" ] || [ "$SCHEMA_NAME" = "$FULL" ]; then
    continue
  fi
  OUT_FILE="${PROC_EXPORT_DIR}/${SCHEMA_NAME}.${PROC_NAME}.sql"
  DEF_QUERY=$(cat <<SQL
SET NOCOUNT ON;
SELECT m.definition
FROM sys.sql_modules m
JOIN sys.objects o ON m.object_id = o.object_id
JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE s.name = N'${SCHEMA_NAME}' AND o.name = N'${PROC_NAME}' AND o.type = 'P';
SQL
)
  "${SQLCMD[@]}" -Q "${DEF_QUERY}" | tr -d '\r' > "${OUT_FILE}"
  echo "[export_proc_source] wrote ${SCHEMA_NAME}.${PROC_NAME}.sql ($(wc -l < "${OUT_FILE}" | tr -d ' ') lines)"
  COUNT=$((COUNT + 1))
done

echo "[export_proc_source] exported ${COUNT} proc(s) to ${PROC_EXPORT_DIR}/"
echo "[export_proc_source] vendored teaching copies in ${SCRIPT_DIR}/ were left unchanged."
