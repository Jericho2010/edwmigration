#!/usr/bin/env bash
# Echo the Python interpreter for EDW tools (prefer repo .venv).
# Usage: PY="$(./agents/tools/resolve_python.sh)"; "$PY" agents/tools/mlflow_observe.py ...
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VENV_PY="${REPO_ROOT}/.venv/bin/python"

if [ -x "$VENV_PY" ]; then
  printf '%s\n' "$VENV_PY"
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  command -v python3
  exit 0
fi

echo "[resolve_python] ERROR: no .venv/bin/python and no python3 on PATH" >&2
exit 1
