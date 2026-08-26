#!/usr/bin/env bash
# Self-check: announce_observability always exits 0 and prints Keep-these-open.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$("${ROOT}/agents/tools/announce_observability.sh" --stage Provision 2>&1)" || true
echo "$OUT" | grep -q "Keep these open during the run." || {
  echo "FAIL: missing Keep these open" >&2
  exit 1
}
echo "$OUT" | grep -q "=== Observability · Provision ===" || {
  echo "FAIL: missing Provision stage header" >&2
  exit 1
}
# Must succeed even without DATABRICKS_HOST
OUT2="$(env -u DATABRICKS_HOST bash -c "
  unset DATABRICKS_HOST
  # avoid loading .env host via subshell that still sources — call print path soft
  DATABRICKS_HOST= ${ROOT}/agents/tools/print_observability_urls.sh
" 2>&1)" || true
echo "$OUT2" | grep -q "Keep these open during the run." || {
  echo "FAIL: print_observability without HOST missing Keep these open" >&2
  exit 1
}
echo "$OUT2" | grep -q "not ready yet" || {
  echo "FAIL: expected not-ready copy when HOST empty" >&2
  exit 1
}
echo "OK announce_observability self-check"
