#!/usr/bin/env bash
# Soft status for edw-start menu (no hard fails; no Azure/SQL bootstrap).
# Usage: ./agents/tools/start_status.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env || true
  set +a
fi

echo "[start_status] repo_root=${REPO_ROOT}"

if [ -f Makefile ] && [ -d .cursor/agents ] && [ -d agents/tools ]; then
  echo "[start_status] OK  workspace looks like edwmigration root"
else
  echo "[start_status] WARN open the git root (folder with Makefile + .cursor/)"
fi

for a in edw-start edw-demo-guide edw-coordinator edw-assess edw-convert edw-test edw-gate; do
  if [ -f ".cursor/agents/${a}.md" ]; then
    echo "[start_status] OK  agent ${a}"
  else
    echo "[start_status] WARN agent missing: ${a}  -> run make sync-prompts"
  fi
done

if [ -f .env ]; then
  echo "[start_status] OK  .env present (SOURCE_TYPE=${SOURCE_TYPE:-unset} CATALOG=${DATABRICKS_CATALOG:-unset})"
else
  echo "[start_status] INFO .env not present yet (Track A materialize or Track B copy from infra/azure/.env.example)"
fi

if [ -f agents/out/CURRENT_RUN ]; then
  echo "[start_status] INFO CURRENT_RUN=$(tr -d '[:space:]' < agents/out/CURRENT_RUN)"
else
  echo "[start_status] INFO no active CURRENT_RUN"
fi

if command -v az >/dev/null 2>&1; then
  if az account show >/dev/null 2>&1; then
    echo "[start_status] OK  Azure CLI session"
  else
    echo "[start_status] INFO Azure CLI installed but not logged in (az login) — needed for Track A"
  fi
else
  echo "[start_status] INFO az not on PATH — needed for Track A bootstrap"
fi

if command -v databricks >/dev/null 2>&1; then
  if databricks current-user me >/dev/null 2>&1; then
    echo "[start_status] OK  Databricks CLI session"
  else
    echo "[start_status] INFO Databricks CLI installed but not authenticated"
  fi
else
  echo "[start_status] INFO databricks CLI not on PATH"
fi

echo "[start_status] done (soft report only — choose a menu item to begin)"
exit 0
