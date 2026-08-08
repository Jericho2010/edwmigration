#!/usr/bin/env bash
# Resolve edwmigration repo root for Cursor hooks (portable; not cwd-dependent).
set -euo pipefail
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer shared tool (script-anchored). Fallback: walk from this hooks dir.
if [ -x "${HOOK_DIR}/../../agents/tools/repo_root.sh" ]; then
  "${HOOK_DIR}/../../agents/tools/repo_root.sh"
  exit $?
fi
# Inline fallback if tools script missing
d="$(cd "${HOOK_DIR}/../.." && pwd)"
if [ -f "${d}/Makefile" ] && [ -d "${d}/.cursor" ]; then
  printf '%s\n' "$d"
  exit 0
fi
echo "[_repo_root] ERROR: cannot resolve repo root" >&2
exit 1
