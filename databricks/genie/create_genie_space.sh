#!/usr/bin/env bash
# create_genie_space.sh — deploy the "EDW Migration Copilot" Genie space.
#
# Idempotent: creates the space, or updates it in place if a space with the
# same title already exists. Config lives in space_config.json (serialized
# Genie space, version 2): ops.* migration tables + gold marts, vocabulary
# instructions, and certified example Q&A.
#
# Usage:
#   ./databricks/genie/create_genie_space.sh
#
# Env: DATABRICKS_HOST / DATABRICKS_TOKEN / DATABRICKS_WAREHOUSE_ID
# (sourced from .env if present). Requires jq + databricks CLI.
#
# Prereq: the medallion job must have run so edw_migration.ops.* and
# edw_migration.gold.* exist (make demo, or docs/runbook.md §§1–4).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG="${SCRIPT_DIR}/space_config.json"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

: "${DATABRICKS_WAREHOUSE_ID:?DATABRICKS_WAREHOUSE_ID must be set}"

for tool in jq databricks; do
  command -v "$tool" >/dev/null 2>&1 || { echo "[genie] $tool is required" >&2; exit 1; }
done

TITLE="$(jq -r '.title' "$CONFIG")"
DESCRIPTION="$(jq -r '.description' "$CONFIG")"
SERIALIZED="$(jq -c '.serialized_space' "$CONFIG")"

# Idempotency: find an existing space with this title.
SPACE_ID="$(
  databricks api get /api/2.0/genie/spaces \
    | jq -r --arg t "$TITLE" '.spaces // [] | map(select(.title == $t)) | .[0].space_id // empty'
)"

PAYLOAD="$(jq -n \
  --arg wid "$DATABRICKS_WAREHOUSE_ID" \
  --arg title "$TITLE" \
  --arg desc "$DESCRIPTION" \
  --argjson ser "$SERIALIZED" \
  '{warehouse_id: $wid, title: $title, description: $desc, serialized_space: ($ser | tostring)}')"

if [ -n "$SPACE_ID" ]; then
  echo "[genie] updating existing space ${SPACE_ID} ('${TITLE}') ..."
  databricks api patch "/api/2.0/genie/spaces/${SPACE_ID}" --json "$PAYLOAD" >/dev/null
else
  echo "[genie] creating space '${TITLE}' ..."
  SPACE_ID="$(databricks api post /api/2.0/genie/spaces --json "$PAYLOAD" | jq -r '.space_id // .id // empty')"
fi

if [ -z "$SPACE_ID" ]; then
  echo "[genie] ERROR: no space_id returned" >&2
  exit 1
fi

echo "[genie] done. Open: ${DATABRICKS_HOST%/}/genie/rooms/${SPACE_ID}"
