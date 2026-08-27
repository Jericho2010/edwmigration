#!/usr/bin/env bash
# Databricks CLI with matching-profile PAT overlay (HOST in .env, no TOKEN).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "${ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${ROOT}/.env" || true
  set +a
fi
# shellcheck disable=SC1091
. "${ROOT}/agents/tools/apply_databricks_cli_auth.sh"
exec databricks "$@"
