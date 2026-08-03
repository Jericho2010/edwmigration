#!/usr/bin/env bash
# Render SQL templates: substitute catalog / federation placeholders into
# databricks/_rendered/ for deploy and run_sql.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

: "${DATABRICKS_CATALOG:=edw_migration}"
: "${AZ_SQL_ADMIN:=edwadmin}"
: "${AZ_SQL_DB:=WideWorldImportersDW}"
: "${FOREIGN_CATALOG:=wwi_dw_fed}"
: "${CONNECTION_NAME:=azure_sql_edw}"
: "${DATABRICKS_SECRET_SCOPE:=edw-migration}"

HOST="${AZ_SQL_HOST:-}"
if [ -z "$HOST" ] && [ -n "${AZ_SQL_SERVER:-}" ]; then
  HOST="${AZ_SQL_SERVER}.database.windows.net"
fi
: "${HOST:?Set AZ_SQL_HOST or AZ_SQL_SERVER for federation render}"

OUT="${REPO_ROOT}/databricks/_rendered"
rm -rf "$OUT"
mkdir -p "$OUT"

# Copy tree then substitute in place under _rendered.
cp -a "${REPO_ROOT}/databricks/uc" "${OUT}/uc"
cp -a "${REPO_ROOT}/databricks/bronze" "${OUT}/bronze" 2>/dev/null || mkdir -p "${OUT}/bronze"
cp -a "${REPO_ROOT}/databricks/silver" "${OUT}/silver" 2>/dev/null || mkdir -p "${OUT}/silver"
cp -a "${REPO_ROOT}/databricks/gold" "${OUT}/gold" 2>/dev/null || mkdir -p "${OUT}/gold"
cp -a "${REPO_ROOT}/databricks/tests" "${OUT}/tests" 2>/dev/null || mkdir -p "${OUT}/tests"
if [ -d "${REPO_ROOT}/databricks/generated" ]; then
  cp -a "${REPO_ROOT}/databricks/generated" "${OUT}/generated"
fi

# Prefer generated land/reconcile when present in repo (copied above).
if [ -f "${REPO_ROOT}/databricks/generated/10_land_all.sql" ]; then
  mkdir -p "${OUT}/bronze"
  cp "${REPO_ROOT}/databricks/generated/10_land_all.sql" "${OUT}/bronze/10_land_all.sql"
fi
if [ -f "${REPO_ROOT}/databricks/generated/reconcile.sql" ]; then
  mkdir -p "${OUT}/tests"
  cp "${REPO_ROOT}/databricks/generated/reconcile.sql" "${OUT}/tests/reconcile.sql"
fi

while IFS= read -r -d '' f; do
  # shellcheck disable=SC2016
  sed -i \
    -e "s/__UC_CATALOG__/${DATABRICKS_CATALOG}/g" \
    -e "s/__FOREIGN_CATALOG__/${FOREIGN_CATALOG}/g" \
    -e "s/__CONNECTION_NAME__/${CONNECTION_NAME}/g" \
    -e "s/__SECRET_SCOPE__/${DATABRICKS_SECRET_SCOPE}/g" \
    -e "s/{{AZ_SQL_HOST}}/${HOST}/g" \
    -e "s/{{AZ_SQL_ADMIN}}/${AZ_SQL_ADMIN}/g" \
    -e "s/{{AZ_SQL_DB}}/${AZ_SQL_DB}/g" \
    -e "s/edw_migration\./${DATABRICKS_CATALOG}./g" \
    "$f"
done < <(find "$OUT" -type f -name '*.sql' -print0)

echo "[render_sql] catalog=${DATABRICKS_CATALOG} foreign=${FOREIGN_CATALOG} host=${HOST} -> ${OUT}"
