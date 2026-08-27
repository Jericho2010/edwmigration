#!/usr/bin/env bash
# wake_sources.sh — wake Azure SQL (AutoPause) AND the SQL warehouse before make run.
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

echo "[wake_sources] warehouse + source AutoPause wakeup"

if [ -n "${DATABRICKS_WAREHOUSE_ID:-}" ]; then
  "${REPO_ROOT}/agents/tools/databricks_cli.sh" warehouses start "$DATABRICKS_WAREHOUSE_ID" >/dev/null 2>&1 || true
  echo "[wake_sources] warehouse start issued id=${DATABRICKS_WAREHOUSE_ID}"
else
  echo "[wake_sources] WARN DATABRICKS_WAREHOUSE_ID unset" >&2
fi

ST="${SOURCE_TYPE:-sqlserver}"
if [ "$ST" = "sqlserver" ] || [ "$ST" = "azure_sql" ]; then
  if command -v sqlcmd >/dev/null 2>&1 && [ -n "${AZ_SQL_SERVER:-}${SOURCE_HOST:-}" ]; then
    SERVER="${AZ_SQL_HOST:-${SOURCE_HOST:-${AZ_SQL_SERVER}.database.windows.net}}"
    USER="${AZ_SQL_ADMIN:-${SOURCE_USER:-}}"
    PASS="${AZ_SQL_PASSWORD:-${SOURCE_PASSWORD:-}}"
    DB="${AZ_SQL_DB:-${SOURCE_DATABASE:-}}"
    echo "[wake_sources] sqlcmd SELECT 1 on ${SERVER} / ${DB}"
    sqlcmd -S "$SERVER" -U "$USER" -P "$PASS" -d "$DB" -C -l 60 -Q "SELECT 1" >/dev/null
  else
    echo "[wake_sources] sqlcmd skipped (missing sqlcmd or Azure SQL env); trying federated SELECT"
    if [ -n "${DATABRICKS_WAREHOUSE_ID:-}" ]; then
      "${REPO_ROOT}/agents/tools/run_sql.sh" --sql "SELECT 1" >/dev/null || true
    fi
  fi
else
  echo "[wake_sources] SOURCE_TYPE=${ST} — warehouse-only wakeup"
  if [ -n "${DATABRICKS_WAREHOUSE_ID:-}" ]; then
    "${REPO_ROOT}/agents/tools/run_sql.sh" --sql "SELECT 1" >/dev/null || true
  fi
fi

echo "[wake_sources] done"
