#!/usr/bin/env bash
# _flush_events.sh — flush buffered agent events to edw_migration.ops.agent_events
# via agents/tools/run_sql.sh (Statement Execution API).
set -euo pipefail

RUN_ID="${1:?usage: _flush_events.sh <run_id>}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BUF_FILE="${REPO_ROOT}/agents/out/${RUN_ID}/events.buf.jsonl"
UC_TABLE="edw_migration.ops.agent_events"
RUN_SQL="${REPO_ROOT}/agents/tools/run_sql.sh"

if [ ! -s "$BUF_FILE" ]; then
  exit 0
fi

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[_flush_events] python3 required; skipping flush." >&2
  exit 0
fi

SQL="$(python3 - "$BUF_FILE" "$UC_TABLE" <<'PY'
import json, sys
path, table = sys.argv[1], sys.argv[2]

def esc(v):
    return "'" + str(v or "").replace("'", "''") + "'"

rows = []
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        o = json.loads(line)
        rows.append(
            "("
            + ",".join([
                esc(o.get("run_id")),
                esc(o.get("agent")),
                esc(o.get("event")),
                esc(o.get("tool")),
                esc(o.get("detail")),
                "TIMESTAMP" + esc(o.get("ts")),
            ])
            + ")"
        )
if not rows:
    sys.exit(0)
print(f"INSERT INTO {table} (run_id, agent, event, tool, detail, ts) VALUES " + ",".join(rows))
PY
)"

if [ -z "${SQL:-}" ]; then
  exit 0
fi

if [ ! -x "$RUN_SQL" ]; then
  echo "[_flush_events] ${RUN_SQL} missing or not executable; events remain buffered." >&2
  exit 0
fi

if "$RUN_SQL" --sql "$SQL" >/dev/null 2>&1; then
  : > "$BUF_FILE"
  echo "[_flush_events] flushed ${RUN_ID} to ${UC_TABLE}." >&2
else
  echo "[_flush_events] WARNING: flush failed; events remain buffered." >&2
fi
exit 0
