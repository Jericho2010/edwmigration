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
# The Statement Execution API runs ONE statement per call. Files with several
# statements are split on ';' at end-of-line (naive) and executed in order.
# Files containing SQL scripting (a BEGIN keyword) are sent whole, so wrap
# scripting in a single BEGIN...END block.
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

for tool in jq databricks python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[run_sql] $tool is required" >&2
    exit 1
  fi
done

# Split into statements unless the input uses SQL scripting (BEGIN...END).
STMT_DIR="$(mktemp -d)"
trap 'rm -rf "$STMT_DIR"' EXIT

if printf '%s' "$SQL" | grep -qE '^[[:space:]]*BEGIN([[:space:]]|$)'; then
  printf '%s' "$SQL" > "${STMT_DIR}/stmt_001.sql"
else
  python3 - "$SQL" "$STMT_DIR" <<'PY'
import re, sys
sql, outdir = sys.argv[1], sys.argv[2]
parts = [p.strip() for p in re.split(r';[ \t]*\r?\n', sql)]
n = 0
for p in parts:
    # skip fragments that are empty or comments only
    body = re.sub(r'--[^\n]*', '', p).strip()
    if not body:
        continue
    n += 1
    with open(f"{outdir}/stmt_{n:03d}.sql", "w") as f:
        f.write(p)
PY
fi

run_one() {
  local stmt_file="$1"
  local stmt payload tmp status stmt_id poll
  stmt="$(cat "$stmt_file")"

  payload="$(jq -n \
    --arg wid "$DATABRICKS_WAREHOUSE_ID" \
    --arg stmt "$stmt" \
    --arg wait "$WAIT_TIMEOUT" \
    '{warehouse_id: $wid, statement: $stmt, wait_timeout: $wait, on_wait_timeout: "CONTINUE"}')"

  tmp="$(mktemp)"
  databricks api post /api/2.0/sql/statements --json "$payload" >"$tmp"

  status="$(jq -r '.status.state // empty' "$tmp")"
  stmt_id="$(jq -r '.statement_id // empty' "$tmp")"

  poll=0
  while [ "$status" = "PENDING" ] || [ "$status" = "RUNNING" ]; do
    poll=$((poll + 1))
    if [ "$poll" -gt 60 ]; then
      echo "[run_sql] timed out waiting for statement ${stmt_id}" >&2
      rm -f "$tmp"
      return 1
    fi
    sleep 5
    databricks api get "/api/2.0/sql/statements/${stmt_id}" >"$tmp"
    status="$(jq -r '.status.state // empty' "$tmp")"
  done

  if [ "$status" != "SUCCEEDED" ]; then
    echo "[run_sql] FAILED state=${status} in $(basename "$stmt_file")" >&2
    jq -r '.status.error.message // .status // .' "$tmp" >&2
    rm -f "$tmp"
    return 1
  fi

  # Print tabular result if present
  if jq -e '.result.data_array' "$tmp" >/dev/null 2>&1; then
    jq -r '
      (.manifest.schema.columns // [] | map(.name)) as $cols
      | ($cols | @tsv),
        (.result.data_array[] | map(. // "") | @tsv)
    ' "$tmp"
  fi
  rm -f "$tmp"
}

N_STMTS="$(find "$STMT_DIR" -name 'stmt_*.sql' | wc -l)"
echo "[run_sql] executing ${N_STMTS} statement(s) on warehouse ${DATABRICKS_WAREHOUSE_ID} ..." >&2

for stmt_file in "$STMT_DIR"/stmt_*.sql; do
  run_one "$stmt_file"
done

echo "[run_sql] all ${N_STMTS} statement(s) SUCCEEDED" >&2
