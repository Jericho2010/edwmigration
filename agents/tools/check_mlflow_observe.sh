#!/usr/bin/env bash
# Check MLflow observe readiness (venv + import + optional Databricks host).
# Soft by default (exit 0). Use --strict to exit 1 when observe cannot record.
#
# Usage:
#   ./agents/tools/check_mlflow_observe.sh
#   ./agents/tools/check_mlflow_observe.sh --strict
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STRICT=0
for a in "$@"; do
  case "$a" in
    --strict) STRICT=1 ;;
  esac
done

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

PY="$("${REPO_ROOT}/agents/tools/resolve_python.sh")"
ISSUES=0
VER_FILE="$(mktemp)"
trap 'rm -f "$VER_FILE"' EXIT

ok() { echo "[mlflow_check] OK  $1"; }
warn() {
  echo "[mlflow_check] WARN $1"
  echo "[mlflow_check]      -> $2"
  ISSUES=$((ISSUES + 1))
}

if [ -x "${REPO_ROOT}/.venv/bin/python" ]; then
  ok "repo .venv present (${PY})"
else
  warn "repo .venv missing" "make observe-setup"
fi

if "$PY" -c "import mlflow; print(mlflow.__version__)" >"$VER_FILE" 2>/dev/null; then
  VER="$(tr -d '[:space:]' < "$VER_FILE")"
  MAJOR="${VER%%.*}"
  REST="${VER#*.}"
  MINOR="${REST%%.*}"
  if [ "${MAJOR:-0}" -gt 3 ] || { [ "${MAJOR:-0}" -eq 3 ] && [ "${MINOR:-0}" -ge 8 ]; }; then
    ok "mlflow importable (version=${VER})"
  else
    warn "mlflow ${VER} is older than 3.8" "make observe-setup  (pip install 'mlflow>=3.8')"
  fi
else
  warn "mlflow not importable with ${PY}" "make observe-setup"
fi

if [ -n "${DATABRICKS_HOST:-}" ]; then
  ok "DATABRICKS_HOST set (tracking can use databricks URI)"
else
  warn "DATABRICKS_HOST unset" "Set DATABRICKS_HOST in .env (same as Databricks CLI)"
fi

if [ "$ISSUES" -eq 0 ]; then
  echo "[mlflow_check] ready — live traces can record"
  exit 0
fi

echo "[mlflow_check] not fully ready (issues=${ISSUES}) — migration still runs; traces soft no-op until fixed"
if [ "$STRICT" -eq 1 ]; then
  exit 1
fi
exit 0
