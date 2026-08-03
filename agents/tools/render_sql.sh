#!/usr/bin/env bash
# Render SQL templates: substitute catalog / federation placeholders into
# databricks/_rendered/ for deploy and run_sql.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Load .env without clobbering vars already set in the environment (CI / overrides).
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

: "${DATABRICKS_CATALOG:=edw_migration}"
: "${DATABRICKS_SECRET_SCOPE:=edw-migration}"
: "${SOURCE_HOST:?Set SOURCE_HOST (or AZ_SQL_HOST / AZ_SQL_SERVER for sqlserver)}"
: "${SOURCE_DATABASE:?Set SOURCE_DATABASE (or AZ_SQL_DB)}"
: "${SOURCE_USER:?Set SOURCE_USER (or AZ_SQL_ADMIN)}"

OUT="${REPO_ROOT}/databricks/_rendered"
rm -rf "$OUT"
mkdir -p "$OUT"

cp -a "${REPO_ROOT}/databricks/uc" "${OUT}/uc"
cp -a "${REPO_ROOT}/databricks/bronze" "${OUT}/bronze" 2>/dev/null || mkdir -p "${OUT}/bronze"
cp -a "${REPO_ROOT}/databricks/silver" "${OUT}/silver" 2>/dev/null || mkdir -p "${OUT}/silver"
cp -a "${REPO_ROOT}/databricks/gold" "${OUT}/gold" 2>/dev/null || mkdir -p "${OUT}/gold"
cp -a "${REPO_ROOT}/databricks/tests" "${OUT}/tests" 2>/dev/null || mkdir -p "${OUT}/tests"
if [ -d "${REPO_ROOT}/databricks/generated" ]; then
  cp -a "${REPO_ROOT}/databricks/generated" "${OUT}/generated"
fi

if [ -f "${REPO_ROOT}/databricks/generated/10_land_all.sql" ]; then
  mkdir -p "${OUT}/bronze"
  cp "${REPO_ROOT}/databricks/generated/10_land_all.sql" "${OUT}/bronze/10_land_all.sql"
fi
if [ -f "${REPO_ROOT}/databricks/generated/reconcile.sql" ]; then
  mkdir -p "${OUT}/tests"
  cp "${REPO_ROOT}/databricks/generated/reconcile.sql" "${OUT}/tests/reconcile.sql"
fi

FED_FILE="${OUT}/uc/01_federation_setup.sql"
CONN_TMP="$(mktemp)"
case "$SOURCE_TYPE" in
  sqlserver)
    cat >"$CONN_TMP" <<'EOF'
CREATE CONNECTION IF NOT EXISTS __CONNECTION_NAME__
  TYPE SQLSERVER
  OPTIONS (
    host '{{SOURCE_HOST}}',
    port '{{SOURCE_PORT}}',
    user '{{SOURCE_USER}}',
    password secret('__SECRET_SCOPE__', '__PASSWORD_SECRET_KEY__'),
    trustServerCertificate 'false'
  );
EOF
    ;;
  mysql)
    cat >"$CONN_TMP" <<'EOF'
CREATE CONNECTION IF NOT EXISTS __CONNECTION_NAME__
  TYPE MYSQL
  OPTIONS (
    host '{{SOURCE_HOST}}',
    port '{{SOURCE_PORT}}',
    user '{{SOURCE_USER}}',
    password secret('__SECRET_SCOPE__', '__PASSWORD_SECRET_KEY__')
  );
EOF
    ;;
esac

export RENDER_FED_FILE="$FED_FILE"
export RENDER_CONN_TMP="$CONN_TMP"
export RENDER_CATALOG="$DATABRICKS_CATALOG"
export RENDER_FOREIGN="$FOREIGN_CATALOG"
export RENDER_CONN_NAME="$CONNECTION_NAME"
export RENDER_SCOPE="$DATABRICKS_SECRET_SCOPE"
export RENDER_PSK="$PASSWORD_SECRET_KEY"
export RENDER_CTYPE="$CONNECTION_TYPE"
export RENDER_HOST="$SOURCE_HOST"
export RENDER_PORT="$SOURCE_PORT"
export RENDER_USER="$SOURCE_USER"
export RENDER_DB="$SOURCE_DATABASE"
export RENDER_OUT="$OUT"

python3 <<'PY'
import os
from pathlib import Path

fed = Path(os.environ["RENDER_FED_FILE"])
block = Path(os.environ["RENDER_CONN_TMP"]).read_text().strip() + "\n"
marker = "-- __FEDERATION_CONNECTION_BLOCK__ (injected by render_sql.sh for SQLSERVER vs MYSQL)"
text = fed.read_text()
if marker not in text:
    raise SystemExit("federation marker missing in 01_federation_setup.sql")
fed.write_text(text.replace(marker, block))

subs = [
    ("__UC_CATALOG__", os.environ["RENDER_CATALOG"]),
    ("__FOREIGN_CATALOG__", os.environ["RENDER_FOREIGN"]),
    ("__CONNECTION_NAME__", os.environ["RENDER_CONN_NAME"]),
    ("__SECRET_SCOPE__", os.environ["RENDER_SCOPE"]),
    ("__PASSWORD_SECRET_KEY__", os.environ["RENDER_PSK"]),
    ("__CONNECTION_TYPE__", os.environ["RENDER_CTYPE"]),
    ("{{SOURCE_HOST}}", os.environ["RENDER_HOST"]),
    ("{{SOURCE_PORT}}", os.environ["RENDER_PORT"]),
    ("{{SOURCE_USER}}", os.environ["RENDER_USER"]),
    ("{{SOURCE_DATABASE}}", os.environ["RENDER_DB"]),
    ("{{AZ_SQL_HOST}}", os.environ["RENDER_HOST"]),
    ("{{AZ_SQL_ADMIN}}", os.environ["RENDER_USER"]),
    ("{{AZ_SQL_DB}}", os.environ["RENDER_DB"]),
]

out = Path(os.environ["RENDER_OUT"])
for path in out.rglob("*.sql"):
    content = path.read_text()
    for old, new in subs:
        content = content.replace(old, new)
    # Legacy default catalog name → user catalog (word-boundary-ish)
    content = content.replace("edw_migration.", os.environ["RENDER_CATALOG"] + ".")
    path.write_text(content)
PY
rm -f "$CONN_TMP"

echo "[render_sql] type=${SOURCE_TYPE} catalog=${DATABRICKS_CATALOG} foreign=${FOREIGN_CATALOG} host=${SOURCE_HOST} -> ${OUT}"
