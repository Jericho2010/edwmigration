# shellcheck shell=bash
# Resolve SOURCE_* from SOURCE_* and/or legacy AZ_SQL_* (demo pack).
# Source this file after .env is loaded:  . agents/tools/resolve_source_env.sh
#
# Sets: SOURCE_TYPE SOURCE_HOST SOURCE_PORT SOURCE_DATABASE SOURCE_USER SOURCE_PASSWORD
#       FOREIGN_CATALOG CONNECTION_NAME PASSWORD_SECRET_KEY CONNECTION_TYPE

: "${SOURCE_TYPE:=sqlserver}"
SOURCE_TYPE="$(printf '%s' "$SOURCE_TYPE" | tr '[:upper:]' '[:lower:]')"

case "$SOURCE_TYPE" in
  sqlserver|mysql) ;;
  *)
    echo "[resolve_source_env] SOURCE_TYPE must be sqlserver or mysql (got: ${SOURCE_TYPE})" >&2
    # Sourced by callers: prefer return; fall back when executed directly.
    # shellcheck disable=SC2317
    return 1 || exit 1
    ;;
esac

# Map demo AZ_SQL_* → SOURCE_* when SOURCE_* unset (sqlserver path).
if [ "$SOURCE_TYPE" = "sqlserver" ]; then
  if [ -z "${SOURCE_HOST:-}" ]; then
    if [ -n "${AZ_SQL_HOST:-}" ]; then
      SOURCE_HOST="${AZ_SQL_HOST}"
    elif [ -n "${AZ_SQL_SERVER:-}" ]; then
      SOURCE_HOST="${AZ_SQL_SERVER}.database.windows.net"
    fi
  fi
  : "${SOURCE_PORT:=1433}"
  : "${SOURCE_DATABASE:=${AZ_SQL_DB:-WideWorldImportersDW}}"
  : "${SOURCE_USER:=${AZ_SQL_ADMIN:-edwadmin}}"
  : "${SOURCE_PASSWORD:=${AZ_SQL_PASSWORD:-}}"
  : "${FOREIGN_CATALOG:=wwi_dw_fed}"
  : "${CONNECTION_NAME:=azure_sql_edw}"
  CONNECTION_TYPE=SQLSERVER
  # Prefer unified key; sqlserver also keeps azure-sql-password alias for bootstrap compat.
  PASSWORD_SECRET_KEY="${PASSWORD_SECRET_KEY:-source-password}"
else
  : "${SOURCE_PORT:=3306}"
  : "${FOREIGN_CATALOG:=mysql_fed}"
  : "${CONNECTION_NAME:=azure_mysql_edw}"
  CONNECTION_TYPE=MYSQL
  PASSWORD_SECRET_KEY="${PASSWORD_SECRET_KEY:-source-password}"
fi

export SOURCE_TYPE SOURCE_HOST SOURCE_PORT SOURCE_DATABASE SOURCE_USER SOURCE_PASSWORD
export FOREIGN_CATALOG CONNECTION_NAME CONNECTION_TYPE PASSWORD_SECRET_KEY
