#!/usr/bin/env bash
# run_sql.sh — execute SQL via the Databricks Statement Execution API.
#
# `databricks sql execute` is NOT a real CLI command. Use this wrapper instead.
#
# Usage:
#   ./agents/tools/run_sql.sh --sql "SELECT 1"
#   ./agents/tools/run_sql.sh --file databricks/uc/01_federation_setup.sql
#
# Env:
#   DATABRICKS_HOST / DATABRICKS_TOKEN (or auth profile)
#   DATABRICKS_WAREHOUSE_ID (required)
#
# Multi-statement files: statements are split on ';' (naive). Prefer one
# logical script per file, or wrap scripting in a single BEGIN...END block.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

: "${DATABRICKS_WAREHOUSE_ID:?DATABRICKS_WAREHOUSE_ID must be set}"

SQL=""
FILE=""
WAIT_TIMEOUT="${SQL_WAIT_TIMEOUT:-50s}"

while [ $# -gt 0 ]; do
  case "$1" in
    --sql) SQL="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --wait) WAIT_TIMEOUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$FILE" ]; then
  if [ ! -f "$FILE" ]; then
    echo "[run_sql] file not found: $FILE" >&2
    exit 1
  fi
  SQL="$(cat "$FILE")"
fi

if [ -z "$SQL" ]; then
  echo "usage: run_sql.sh --sql 'SELECT 1' | --file path.sql" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[run_sql] jq is required" >&2
  exit 1
fi

if ! command -v databricks >/dev/null 2>&1; then
  echo "[run_sql] databricks CLI is required" >&2
  exit 1
fi

# Build JSON payload with proper escaping via jq.
PAYLOAD="$(jq -n \
  --arg wid "$DATABRICKS_WAREHOUSE_ID" \
  --arg stmt "$SQL" \
  --arg wait "$WAIT_TIMEOUT" \
  '{warehouse_id: $wid, statement: $stmt, wait_timeout: $wait, on_wait_timeout: "CONTINUE"}')"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "[run_sql] submitting statement to warehouse ${DATABRICKS_WAREHOUSE_ID} ..." >&2
databricks api post /api/2.0/sql/statements --json "$PAYLOAD" >"$TMP"

STATUS="$(jq -r '.status.state // empty' "$TMP")"
STMT_ID="$(jq -r '.statement_id // empty' "$TMP")"

# Poll if still running
POLL=0
while [ "$STATUS" = "PENDING" ] || [ "$STATUS" = "RUNNING" ]; do
  POLL=$((POLL + 1))
  if [ "$POLL" -gt 60 ]; then
    echo "[run_sql] timed out waiting for statement ${STMT_ID}" >&2
    exit 1
  fi
  sleep 5
  databricks api get "/api/2.0/sql/statements/${STMT_ID}" >"$TMP"
  STATUS="$(jq -r '.status.state // empty' "$TMP")"
done

if [ "$STATUS" != "SUCCEEDED" ]; then
  echo "[run_sql] FAILED state=${STATUS}" >&2
  jq -r '.status.error.message // .status // .' "$TMP" >&2
  exit 1
fi

# Print tabular result if present
if jq -e '.result.data_array' "$TMP" >/dev/null 2>&1; then
  jq -r '
    (.manifest.schema.columns // [] | map(.name)) as $cols
    | ($cols | @tsv),
      (.result.data_array[] | map(. // "") | @tsv)
  ' "$TMP"
else
  echo "[run_sql] SUCCEEDED (no result set) statement_id=${STMT_ID}" >&2
fi
