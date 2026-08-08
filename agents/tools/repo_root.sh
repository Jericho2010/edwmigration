#!/usr/bin/env bash
# Echo the absolute path of the edwmigration repo root.
#
# Resolution order:
#   1. Walk up from this script's directory for markers (Makefile + .cursor + agents/tools)
#   2. Walk up from $PWD for the same markers
#   3. git rev-parse --show-toplevel (if inside a git work tree)
#   4. Fail
#
# Usage:
#   ROOT="$(./agents/tools/repo_root.sh)"
#   # or:  REPO_ROOT="$(.cursor/hooks/_repo_root.sh)"  # thin wrapper
set -euo pipefail

is_repo_root() {
  local d="$1"
  [ -f "${d}/Makefile" ] && [ -d "${d}/.cursor" ] && [ -d "${d}/agents/tools" ]
}

walk_up() {
  local d
  d="$(cd "$1" && pwd)"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if is_repo_root "$d"; then
      printf '%s' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ROOT="$(walk_up "$SCRIPT_DIR")"; then
  printf '%s\n' "$ROOT"
  exit 0
fi

if ROOT="$(walk_up "$(pwd)")"; then
  printf '%s\n' "$ROOT"
  exit 0
fi

if GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  if is_repo_root "$GIT_ROOT"; then
    printf '%s\n' "$GIT_ROOT"
    exit 0
  fi
fi

echo "[repo_root] ERROR: could not locate edwmigration root (Makefile + .cursor + agents/tools)" >&2
exit 1
