#!/usr/bin/env bash
# _flush_events.sh — flush the buffered agent events for a run_id to
# edw_migration.ops.agent_events via the Databricks CLI.
#
# Called by log_event.sh (when threshold crossed) and on_subagent_stop.sh
# (final flush). Not wired directly in hooks.json.
#
# Usage:
#   ./_flush_events.sh <run_id>
set -euo pipefail

RUN_ID="${1:?usage: _flush_events.sh <run_id>}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BUF_FILE="${REPO_ROOT}/agents/out/${RUN_ID}/events.buf.jsonl"
UC_TABLE="edw_migration.ops.agent_events"

if [ ! -s "$BUF_FILE" ]; then
  exit 0
fi

# Load .env for DATABRICKS_HOST / TOKEN.
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

# Build a single INSERT VALUES statement from the buffer.
# Each line is a JSON object: {run_id, agent, event, tool, detail, ts}.
# We use jq to project each field into a SQL-safe quoted string, then join
# with commas. This avoids needing a staging table or volume.
if ! command -v jq >/dev/null 2>&1; then
  echo "[_flush_events] jq required; skipping flush (events remain buffered)." >&2
  exit 0
fi

# Build the VALUES clause
VALUES_CLAUSE="$(jq -r '
  @json |
  . as $row |
  "(" +
    "'"'"'" + ($row.run_id // "") + "'"'"'" + "," +
    "'"'"'" + ($row.agent // "") + "'"'"'" + "," +
    "'"'"'" + ($row.event // "") + "'"'"'" + "," +
    "'"'"'" + ($row.tool // "") + "'"'"'" + "," +
    "'"'"'" + ($row.detail // "") + "'"'"'" + "," +
    "'"'"'" + ($row.ts // "") + "'"'"'" +
  ")"
' "$BUF_FILE" | paste -sd, -)"

if [ -z "$VALUES_CLAUSE" ]; then
  exit 0
fi

SQL="INSERT INTO ${UC_TABLE} (run_id, agent, event, tool, detail, ts) VALUES ${VALUES_CLAUSE};"

# Execute via databricks CLI. If DATABRICKS_WAREHOUSE_ID is set, use it; else
# let the CLI pick the default warehouse.
WAREHOUSE_FLAG=""
if [ -n "${DATABRICKS_WAREHOUSE_ID:-}" ]; then
  WAREHOUSE_FLAG="--warehouse-id ${DATABRICKS_WAREHOUSE_ID}"
fi

# shellcheck disable=SC2086
if databricks sql execute ${WAREHOUSE_FLAG} --sql "$SQL" >/dev/null 2>&1; then
  : > "$BUF_FILE"  # truncate on success
  echo "[_flush_events] flushed ${RUN_ID} to ${UC_TABLE}." >&2
else
  echo "[_flush_events] WARNING: databricks sql execute failed; events remain buffered." >&2
  exit 0  # do not fail the hook
fi
