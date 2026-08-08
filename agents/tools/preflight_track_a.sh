#!/usr/bin/env bash
# Track A preflight: tools + auth + warehouse smoke tests.
# Run by edw-demo-guide after kickoff. Exit 0 if ready; exit 1 with remediations.
#
# Usage:
#   ./agents/tools/preflight_track_a.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

FAILS=0
WARNINGS=0

ok() { echo "[preflight] OK  $1"; }
fail() {
  echo "[preflight] FAIL $1"
  echo "[preflight]      -> $2"
  FAILS=$((FAILS + 1))
}
warn() {
  echo "[preflight] WARN $1"
  echo "[preflight]      -> $2"
  WARNINGS=$((WARNINGS + 1))
}

echo "[preflight] Track A smoke checks (tools, auth, warehouse)"

if command -v az >/dev/null 2>&1; then
  ok "az on PATH"
else
  fail "az not on PATH" "Install Azure CLI - see docs/prerequisites.md"
fi

if command -v databricks >/dev/null 2>&1; then
  ok "databricks on PATH"
else
  fail "databricks not on PATH" "Install Databricks CLI 0.281+ - see docs/prerequisites.md"
fi

if command -v python3 >/dev/null 2>&1; then
  ok "python3 on PATH"
else
  fail "python3 not on PATH" "Install Python 3.10+ - see docs/prerequisites.md"
fi

if command -v jq >/dev/null 2>&1; then
  ok "jq on PATH"
else
  fail "jq not on PATH" "Install jq - see docs/prerequisites.md"
fi

if command -v az >/dev/null 2>&1; then
  if az account show >/dev/null 2>&1; then
    ok "Azure CLI session (az account show)"
  else
    fail "Azure CLI not logged in" "az login"
  fi
fi

if command -v databricks >/dev/null 2>&1; then
  if databricks current-user me >/dev/null 2>&1; then
    ok "Databricks CLI session (current-user me)"
    WH_COUNT=0
    if WH_JSON="$(databricks warehouses list --output json 2>/dev/null)"; then
      WH_COUNT="$(printf '%s' "$WH_JSON" | jq 'if type=="array" then length elif .warehouses then (.warehouses|length) else 0 end' 2>/dev/null || echo 0)"
    fi
    # Normalize non-numeric jq noise
    case "${WH_COUNT}" in
      ''|*[!0-9]*) WH_COUNT=0 ;;
    esac
    if [ "${WH_COUNT}" -ge 1 ]; then
      ok "SQL warehouse present (count=${WH_COUNT})"
    else
      fail "No SQL warehouse found" \
        "Create a serverless SQL warehouse in the workspace UI, then say continue"
    fi
  else
    fail "Databricks CLI not authenticated" \
      "databricks auth login --host <your-workspace-url>  (or set DATABRICKS_TOKEN)"
  fi
fi

if command -v sqlpackage >/dev/null 2>&1 || command -v SqlPackage >/dev/null 2>&1; then
  ok "SqlPackage on PATH"
else
  fail "SqlPackage not on PATH" \
    "Install SqlPackage - see docs/prerequisites.md (required for Track A bacpac bootstrap)"
fi

if command -v sqlcmd >/dev/null 2>&1; then
  ok "sqlcmd on PATH"
else
  fail "sqlcmd not on PATH" \
    "Install sqlcmd - see docs/prerequisites.md (required for Track A proc export)"
fi

echo "[preflight] done fails=${FAILS} warnings=${WARNINGS}"
if [ "$FAILS" -gt 0 ]; then
  echo "[preflight] Fix the FAIL remediations above, then say continue."
  echo "[preflight] Logins are interactive/MFA - the agent cannot complete them for you."
  exit 1
fi
exit 0
