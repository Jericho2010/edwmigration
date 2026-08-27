#!/usr/bin/env bash
# teardown_databricks.sh — Remove Databricks demo assets. Azure SQL is untouched.
#
# Default (no flags): bundle + genie + mlflow + catalog + federation + secrets + notebooks.
# Each flag is additive when any flag is passed; omit flags to run all of the
# default set. --local is opt-in (keeps .env so the next setup can reuse Azure).
#
# Usage:
#   ./agents/tools/teardown_databricks.sh              # default set, confirms
#   ./agents/tools/teardown_databricks.sh --yes         # no confirm
#   ./agents/tools/teardown_databricks.sh --mlflow      # only MLflow experiment/runs
#   ./agents/tools/teardown_databricks.sh --bundle --genie --catalog
#   make teardown-databricks
#
# Flags:
#   --bundle        databricks bundle destroy -t dev (job + dashboard + workspace files)
#   --genie         DELETE Genie space by title
#   --mlflow        purge /Shared/edw-migration runs (and the experiment)
#   --catalog       DROP CATALOG ${DATABRICKS_CATALOG} CASCADE
#   --federation    DROP FOREIGN CATALOG + CONNECTION
#   --secrets       databricks secrets delete-scope
#   --notebooks     delete Workspace /Users/<you>/edwmigration_* gallery
#   --local         remove agents/out/* and databricks/_rendered (keeps .env)
#   --local-env     also remove .env
#   --yes           skip interactive confirm
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

if [ -f "${REPO_ROOT}/agents/tools/resolve_source_env.sh" ]; then
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/agents/tools/resolve_source_env.sh" || true
fi

: "${DATABRICKS_CATALOG:=edw_migration}"
: "${FOREIGN_CATALOG:=wwi_dw_fed}"
: "${CONNECTION_NAME:=azure_sql_edw}"
: "${DATABRICKS_SECRET_SCOPE:=edw-migration}"
GENIE_TITLE="$(jq -r '.title // "EDW Migration Copilot"' "${REPO_ROOT}/databricks/genie/space_config.json" 2>/dev/null || echo "EDW Migration Copilot")"

DO_BUNDLE=0
DO_GENIE=0
DO_MLFLOW=0
DO_CATALOG=0
DO_FEDERATION=0
DO_SECRETS=0
DO_NOTEBOOKS=0
DO_LOCAL=0
DO_LOCAL_ENV=0
YES=0
ANY_FLAG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) DO_BUNDLE=1; ANY_FLAG=1; shift ;;
    --genie) DO_GENIE=1; ANY_FLAG=1; shift ;;
    --mlflow) DO_MLFLOW=1; ANY_FLAG=1; shift ;;
    --catalog) DO_CATALOG=1; ANY_FLAG=1; shift ;;
    --federation) DO_FEDERATION=1; ANY_FLAG=1; shift ;;
    --secrets) DO_SECRETS=1; ANY_FLAG=1; shift ;;
    --notebooks) DO_NOTEBOOKS=1; ANY_FLAG=1; shift ;;
    --local) DO_LOCAL=1; ANY_FLAG=1; shift ;;
    --local-env) DO_LOCAL=1; DO_LOCAL_ENV=1; ANY_FLAG=1; shift ;;
    --yes|-y) YES=1; shift ;;
    -h|--help)
      sed -n '1,32p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ "$ANY_FLAG" -eq 0 ]; then
  DO_BUNDLE=1
  DO_GENIE=1
  DO_MLFLOW=1
  DO_CATALOG=1
  DO_FEDERATION=1
  DO_SECRETS=1
  DO_NOTEBOOKS=1
fi

echo
echo "=== teardown-databricks (Azure SQL stays) ==="
echo "  catalog=${DATABRICKS_CATALOG}  foreign=${FOREIGN_CATALOG}  connection=${CONNECTION_NAME}"
[ "$DO_BUNDLE" -eq 1 ] && echo "  [x] bundle destroy (job + dashboard + workspace files)"
[ "$DO_GENIE" -eq 1 ] && echo "  [x] Genie space '${GENIE_TITLE}'"
[ "$DO_MLFLOW" -eq 1 ] && echo "  [x] MLflow experiment /Shared/edw-migration (all runs + experiment)"
[ "$DO_CATALOG" -eq 1 ] && echo "  [x] DROP CATALOG ${DATABRICKS_CATALOG} CASCADE"
[ "$DO_FEDERATION" -eq 1 ] && echo "  [x] DROP CATALOG ${FOREIGN_CATALOG} CASCADE + DROP CONNECTION ${CONNECTION_NAME}"
[ "$DO_SECRETS" -eq 1 ] && echo "  [x] secret scope ${DATABRICKS_SECRET_SCOPE}"
[ "$DO_NOTEBOOKS" -eq 1 ] && echo "  [x] Workspace edwmigration_* notebooks (this user)"
[ "$DO_LOCAL" -eq 1 ] && echo "  [x] local agents/out + databricks/_rendered"
[ "$DO_LOCAL_ENV" -eq 1 ] && echo "  [x] local .env"
echo "  KEEPS: Azure resource group / SQL server / WideWorldImportersDW"
echo

if [ "$YES" -ne 1 ]; then
  printf "Type 'destroy' to continue: "
  read -r confirm
  if [ "${confirm}" != "destroy" ]; then
    echo "[teardown-databricks] aborted."
    exit 1
  fi
fi

RUN_SQL="${REPO_ROOT}/agents/tools/run_sql.sh"
fail() { echo "[teardown-databricks] WARN: $*" >&2; }

if [ "$DO_BUNDLE" -eq 1 ]; then
  echo "[teardown-databricks] bundle destroy -t dev ..."
  # databricks.yml requires warehouse_id; .env HOST without TOKEN also breaks CLI auth.
  export BUNDLE_VAR_warehouse_id="${DATABRICKS_WAREHOUSE_ID:-}"
  export BUNDLE_VAR_catalog="${DATABRICKS_CATALOG:-edw_migration}"
  destroy_args=(-t dev --auto-approve)
  if [ -n "${DATABRICKS_WAREHOUSE_ID:-}" ]; then
    destroy_args+=(--var "warehouse_id=${DATABRICKS_WAREHOUSE_ID}")
  fi
  if ! databricks bundle destroy "${destroy_args[@]}"; then
    fail "bundle destroy failed (job/dashboard may already be gone)"
  fi
fi

if [ "$DO_GENIE" -eq 1 ]; then
  echo "[teardown-databricks] deleting Genie space '${GENIE_TITLE}' ..."
  SPACE_ID="$(
    databricks api get /api/2.0/genie/spaces 2>/dev/null \
      | jq -r --arg t "$GENIE_TITLE" '.spaces // [] | map(select(.title == $t)) | .[0].space_id // empty'
  )" || SPACE_ID=""
  if [ -n "$SPACE_ID" ]; then
    if ! databricks api delete "/api/2.0/genie/spaces/${SPACE_ID}"; then
      fail "Genie DELETE failed for ${SPACE_ID}"
    else
      echo "[teardown-databricks] deleted Genie space ${SPACE_ID}"
    fi
  else
    echo "[teardown-databricks] no Genie space titled '${GENIE_TITLE}'"
  fi
fi

if [ "$DO_MLFLOW" -eq 1 ]; then
  echo "[teardown-databricks] purging MLflow experiment /Shared/edw-migration ..."
  PY="$("${REPO_ROOT}/agents/tools/resolve_python.sh" 2>/dev/null || command -v python3 || true)"
  if [ -n "${PY:-}" ]; then
    "$PY" "${REPO_ROOT}/agents/tools/mlflow_observe.py" experiment-purge --delete-experiment \
      || fail "MLflow experiment-purge failed"
  else
    fail "no python to run experiment-purge"
  fi
fi

if [ "$DO_CATALOG" -eq 1 ]; then
  echo "[teardown-databricks] DROP CATALOG ${DATABRICKS_CATALOG} CASCADE ..."
  if [ -x "$RUN_SQL" ]; then
    "$RUN_SQL" --sql "DROP CATALOG IF EXISTS ${DATABRICKS_CATALOG} CASCADE;" \
      || fail "DROP CATALOG ${DATABRICKS_CATALOG} failed"
  else
    fail "run_sql.sh missing"
  fi
fi

if [ "$DO_FEDERATION" -eq 1 ]; then
  echo "[teardown-databricks] DROP FOREIGN CATALOG ${FOREIGN_CATALOG} + CONNECTION ${CONNECTION_NAME} ..."
  if [ -x "$RUN_SQL" ]; then
    "$RUN_SQL" --sql "
DROP CATALOG IF EXISTS ${FOREIGN_CATALOG} CASCADE;
DROP CONNECTION IF EXISTS ${CONNECTION_NAME};
SELECT 'federation_dropped' AS check_name;
" || fail "DROP foreign catalog/connection failed"
  else
    fail "run_sql.sh missing"
  fi
fi

if [ "$DO_SECRETS" -eq 1 ]; then
  echo "[teardown-databricks] deleting secret scope ${DATABRICKS_SECRET_SCOPE} ..."
  if ! databricks secrets delete-scope "${DATABRICKS_SECRET_SCOPE}"; then
    fail "secrets delete-scope failed (may already be gone)"
  fi
fi

if [ "$DO_NOTEBOOKS" -eq 1 ]; then
  echo "[teardown-databricks] deleting Workspace edwmigration_* notebooks ..."
  python3 "${REPO_ROOT}/agents/tools/publish_run_notebooks.py" --delete-published \
    || fail "notebook folder delete failed"
fi

if [ "$DO_LOCAL" -eq 1 ]; then
  echo "[teardown-databricks] clearing agents/out and databricks/_rendered ..."
  if [ -d "${REPO_ROOT}/agents/out" ]; then
    find "${REPO_ROOT}/agents/out" -mindepth 1 -maxdepth 1 ! -name '.gitkeep' -exec rm -rf {} +
  fi
  rm -rf "${REPO_ROOT}/databricks/_rendered"
fi

if [ "$DO_LOCAL_ENV" -eq 1 ]; then
  echo "[teardown-databricks] removing .env ..."
  rm -f "${REPO_ROOT}/.env"
fi

echo
echo "[teardown-databricks] done. Azure SQL untouched."
echo "Next: make setup  (recreates catalog/federation/job/dashboard/Genie from .env)"
echo "Full Azure wipe remains: make teardown"
