#!/usr/bin/env bash
# Render 01_federation_setup.sql by substituting {{AZ_SQL_HOST}} / {{AZ_SQL_ADMIN}}
# from the environment (.env). Prints rendered SQL to stdout.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

: "${AZ_SQL_SERVER:?AZ_SQL_SERVER must be set}"
: "${AZ_SQL_ADMIN:=edwadmin}"

HOST="${AZ_SQL_HOST:-${AZ_SQL_SERVER}.database.windows.net}"
SRC="${REPO_ROOT}/databricks/uc/01_federation_setup.sql"

sed -e "s/{{AZ_SQL_HOST}}/${HOST}/g" \
    -e "s/{{AZ_SQL_ADMIN}}/${AZ_SQL_ADMIN}/g" \
    "$SRC"
