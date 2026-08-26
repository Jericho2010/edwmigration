#!/usr/bin/env bash
# track_a_provision.sh — Track A materialize → bootstrap → setup with observability banners.
# Run in the **visible parent chat session** (paste each announce block). Do NOT hide inside a mute Task.
#
# Usage:
#   ./agents/tools/track_a_provision.sh
#   DATABRICKS_CATALOG=edw_migration ./agents/tools/track_a_provision.sh
#   ./agents/tools/track_a_provision.sh --skip-materialize
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

SKIP_MATERIALIZE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-materialize) SKIP_MATERIALIZE=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--skip-materialize]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

announce() {
  "${REPO_ROOT}/agents/tools/announce_observability.sh" --stage "$1" || true
}

echo "[edw] Track A provision starting — pasting Provision observability banner first."
announce Provision

if [ "$SKIP_MATERIALIZE" -eq 0 ]; then
  echo "[edw] step=materialize — writing .env (SQL password, unique server, warehouse, catalog)."
  if [ -n "${DATABRICKS_CATALOG:-}" ]; then
    export DATABRICKS_CATALOG
  fi
  "${REPO_ROOT}/agents/tools/materialize_demo_env.sh"
  echo "[edw] step=materialize done."
else
  echo "[edw] step=materialize skipped (--skip-materialize)."
fi

echo "[edw] step=bootstrap starting (minutes: Azure SQL + WWI bacpac + secrets)…"
echo "[edw] Temporary firewall 0.0.0.0/0 for Free Edition egress; teardown removes it."
make bootstrap
echo "[edw] step=bootstrap done."
announce Bootstrap

echo "[edw] step=setup starting (federation + deploy + genie + print-urls)…"
make setup
echo "[edw] step=setup done."
announce Setup

echo "[edw] Track A provision complete. Next: dirty-catalog check (PreMint), then mint + coordinator."
