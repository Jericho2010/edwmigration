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

# Snapshot-then-swap: atomically move the buffer aside so events appended by
# log_event.sh while we flush land in a fresh BUF_FILE instead of being
# truncated away after the INSERT.
SNAP_FILE="${BUF_FILE}.flushing.$$"
mv "$BUF_FILE" "$SNAP_FILE"

restore_snapshot() {
  # Put unflushed events back into the buffer (best effort).
  if [ -s "$SNAP_FILE" ]; then
    cat "$SNAP_FILE" >> "$BUF_FILE"
  fi
  rm -f "$SNAP_FILE"
}

if ! SQL="$(python3 - "$SNAP_FILE" "$UC_TABLE" <<'PY'
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
)"; then
  echo "[_flush_events] WARNING: could not build INSERT; events remain buffered." >&2
  restore_snapshot
  exit 0
fi

if [ -z "${SQL:-}" ]; then
  rm -f "$SNAP_FILE"
  exit 0
fi

if [ ! -x "$RUN_SQL" ]; then
  echo "[_flush_events] ${RUN_SQL} missing or not executable; events remain buffered." >&2
  restore_snapshot
  exit 0
fi

if "$RUN_SQL" --sql "$SQL" >/dev/null 2>&1; then
  rm -f "$SNAP_FILE"
  echo "[_flush_events] flushed ${RUN_ID} to ${UC_TABLE}." >&2
else
  echo "[_flush_events] WARNING: flush failed; events remain buffered." >&2
  restore_snapshot
fi
exit 0
