#!/usr/bin/env bash
# Resolve the active migration run_id for Cursor hooks.
set -euo pipefail
REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CURRENT="${REPO_ROOT}/agents/out/CURRENT_RUN"

if [ -f "$CURRENT" ]; then
  RUN_ID="$(tr -d '[:space:]' < "$CURRENT")"
  if [ -n "$RUN_ID" ] && [ -d "${REPO_ROOT}/agents/out/${RUN_ID}" ]; then
    printf '%s' "$RUN_ID"
    exit 0
  fi
fi

NEWEST="$(ls -1dt "${REPO_ROOT}"/agents/out/*/context.json 2>/dev/null | head -1 || true)"
if [ -n "$NEWEST" ]; then
  basename "$(dirname "$NEWEST")"
  exit 0
fi

printf 'unknown'
