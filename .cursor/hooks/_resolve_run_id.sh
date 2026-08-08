#!/usr/bin/env bash
# Resolve the active migration run_id for Cursor hooks.
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${1:-}" ]; then
  REPO_ROOT="$1"
else
  REPO_ROOT="$("${HOOK_DIR}/_repo_root.sh")"
fi

CURRENT="${REPO_ROOT}/agents/out/CURRENT_RUN"

if [ -f "$CURRENT" ]; then
  RUN_ID="$(tr -d '[:space:]' < "$CURRENT")"
  if [ -n "$RUN_ID" ] && [ -d "${REPO_ROOT}/agents/out/${RUN_ID}" ]; then
    printf '%s' "$RUN_ID"
    exit 0
  fi
fi

# Portable newest context.json (no GNU find -printf)
if command -v python3 >/dev/null 2>&1; then
  NEWEST="$(python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1]) / "agents" / "out"
best = None
best_mtime = -1.0
if root.is_dir():
    for ctx in root.glob("*/context.json"):
        try:
            m = ctx.stat().st_mtime
        except OSError:
            continue
        if m > best_mtime:
            best_mtime = m
            best = ctx.parent.name
print(best or "")
PY
)"
  if [ -n "$NEWEST" ]; then
    printf '%s' "$NEWEST"
    exit 0
  fi
fi

printf 'unknown'
