#!/usr/bin/env bash
# announce_observability.sh — Paste-ready observability banner for provision + run stages.
# Always exits 0 (best-effort). Agents must paste this output into chat immediately.
#
# Usage:
#   ./agents/tools/announce_observability.sh --stage Provision
#   ./agents/tools/announce_observability.sh --stage Setup
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

STAGE="Provision"
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE="${2:-Provision}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--stage Name]"
      echo "Stages: Provision Bootstrap Setup PreMint Mint Discover Land Assess Convert Job Test Gate Done"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; shift ;;
  esac
done

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi
# shellcheck disable=SC1091
. "${REPO_ROOT}/agents/tools/apply_databricks_cli_auth.sh"

echo
echo "=== Observability · ${STAGE} ==="
echo "Keep these open during the run."
echo "Open Control Plane + Genie + Catalog (+ Notebooks after Land, Job after deploy, MLflow observe_url when present) and leave the tabs open."
echo

# URL banner (never fail provision/setup)
if [ -z "${DATABRICKS_HOST:-}" ]; then
  echo "=== Observability ==="
  echo "Keep these open during the run."
  echo "Control Plane: not ready yet — appears after make setup (deploy + genie)."
  echo "Genie: not ready yet — appears after make setup."
  echo "Catalog: not ready yet — appears after make setup."
  echo "Job: not ready yet — appears after make deploy."
  echo "Notebooks: appear after Land (publish_run_notebooks)."
  echo "MLflow traces: appear after mint (mlflow_observe init / ensure_run_events)."
  echo "Until then: watch chat for [edw] heartbeats from track_a_provision / bootstrap."
  echo "================="
  echo
else
  "${REPO_ROOT}/agents/tools/print_observability_urls.sh" 2>/dev/null || {
    echo "=== Observability ==="
    echo "Keep these open during the run."
    echo "Control Plane / Genie: print-urls failed (auth/deploy?) — re-run: make print-urls"
    echo "================="
    echo
  }
fi

# Ops snapshot when possible (also best-effort)
if [ -x "${REPO_ROOT}/agents/tools/observe_status.sh" ]; then
  "${REPO_ROOT}/agents/tools/observe_status.sh" --stage "$STAGE" 2>/dev/null || true
fi

case "$STAGE" in
  Provision|Bootstrap)
    echo "[edw] ${STAGE}: long Azure/Databricks work may follow — chat should show [edw] steps; do not assume hung silence."
    ;;
  Setup)
    echo "[edw] Setup: Control Plane + Genie + Catalog should be openable now; Job after deploy; Notebooks after Land; observe_url joins at Mint."
    ;;
esac

echo
exit 0
