#!/usr/bin/env bash
# Upsert source password into Databricks secret scope for Federation.
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
# shellcheck disable=SC1091
. "${REPO_ROOT}/agents/tools/resolve_source_env.sh"

: "${DATABRICKS_SECRET_SCOPE:=edw-migration}"
: "${SOURCE_PASSWORD:?SOURCE_PASSWORD (or AZ_SQL_PASSWORD) required to upsert secret}"

if ! command -v databricks >/dev/null 2>&1; then
  echo "[upsert_source_secret] databricks CLI required" >&2
  exit 1
fi

databricks secrets create-scope "$DATABRICKS_SECRET_SCOPE" 2>/dev/null \
  || echo "[upsert_source_secret] scope ${DATABRICKS_SECRET_SCOPE} already exists (ok)"

printf '%s' "$SOURCE_PASSWORD" | databricks secrets put-secret \
  "$DATABRICKS_SECRET_SCOPE" source-password --string-from-stdin
echo "[upsert_source_secret] stored source-password in ${DATABRICKS_SECRET_SCOPE}"

if [ "$SOURCE_TYPE" = "sqlserver" ]; then
  printf '%s' "$SOURCE_PASSWORD" | databricks secrets put-secret \
    "$DATABRICKS_SECRET_SCOPE" azure-sql-password --string-from-stdin
  echo "[upsert_source_secret] stored azure-sql-password alias"
fi
