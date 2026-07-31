#!/usr/bin/env bash
# log_event.sh — Cursor hook that buffers structured agent events and flushes
# them to edw_migration.ops.agent_events (Unity Catalog Delta table).
#
# Wired in .cursor/hooks.json for: subagentStart, afterFileEdit,
# afterShellExecution, afterMCPExecution.
#
# failClosed: false — a failed log write must NOT break the agent run.
#
# Buffering: events are appended to agents/out/<run_id>/events.buf.jsonl and
# flushed in batches (every FLUSH_THRESHOLD events) to avoid one UC round-trip
# per event. on_subagent_stop.sh does a final flush.
#
# Hook payload (JSON on stdin): { agent, event, tool, detail, run_id, ... }
# Cursor passes a JSON object describing the lifecycle event. We extract the
# fields we care about and emit a row.
set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
FLUSH_THRESHOLD="${AGENT_EVENT_FLUSH_THRESHOLD:-10}"
UC_TABLE="edw_migration.ops.agent_events"

# ---------------------------------------------------------------------------
# Load .env if present (for DATABRICKS_HOST / TOKEN used by the CLI).
# Hooks run with the workspace cwd, so .env is at the repo root.
# ---------------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

# ---------------------------------------------------------------------------
# Read hook payload from stdin
# ---------------------------------------------------------------------------
PAYLOAD="$(cat || true)"
if [ -z "$PAYLOAD" ]; then
  # Nothing to log; exit 0 so the run continues (failClosed: false).
  exit 0
fi

# Extract fields. Use jq if available, else fall back to grep/sed.
if command -v jq >/dev/null 2>&1; then
  RUN_ID="$(echo "$PAYLOAD" | jq -r '.run_id // "unknown"')"
  AGENT="$(echo "$PAYLOAD" | jq -r '.agent // "coordinator"')"
  EVENT="$(echo "$PAYLOAD" | jq -r '.event // "unknown"')"
  TOOL="$(echo "$PAYLOAD" | jq -r '.tool // ""')"
  DETAIL="$(echo "$PAYLOAD" | jq -r '.detail // "" | gsub("\n"; " ") | .[0:500]')"
else
  RUN_ID="$(echo "$PAYLOAD" | sed -n 's/.*"run_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  AGENT="$(echo "$PAYLOAD"  | sed -n 's/.*"agent"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  EVENT="$(echo "$PAYLOAD" | sed -n 's/.*"event"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  TOOL="$(echo "$PAYLOAD"  | sed -n 's/.*"tool"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  DETAIL=""
  [ -z "$RUN_ID" ] && RUN_ID="unknown"
  [ -z "$AGENT" ]  && AGENT="coordinator"
  [ -z "$EVENT" ]  && EVENT="unknown"
fi

# ---------------------------------------------------------------------------
# Buffer the event
# ---------------------------------------------------------------------------
BUF_DIR="${REPO_ROOT}/agents/out/${RUN_ID}"
mkdir -p "$BUF_DIR"
BUF_FILE="${BUF_DIR}/events.buf.jsonl"

# Emit one JSON line per event (the format ops.agent_events expects).
TS="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
if command -v jq >/dev/null 2>&1; then
  jq -cn \
    --arg run_id "$RUN_ID" \
    --arg agent "$AGENT" \
    --arg event "$EVENT" \
    --arg tool "$TOOL" \
    --arg detail "$DETAIL" \
    --arg ts "$TS" \
    '{run_id:$run_id, agent:$agent, event:$event, tool:$tool, detail:$detail, ts:$ts}' \
    >> "$BUF_FILE"
else
  printf '{"run_id":"%s","agent":"%s","event":"%s","tool":"%s","detail":"%s","ts":"%s"}\n' \
    "$RUN_ID" "$AGENT" "$EVENT" "$TOOL" "$DETAIL" "$TS" >> "$BUF_FILE"
fi

# ---------------------------------------------------------------------------
# Flush if we've crossed the threshold
# ---------------------------------------------------------------------------
COUNT="$(wc -l < "$BUF_FILE" | tr -d ' ')"
if [ "$COUNT" -ge "$FLUSH_THRESHOLD" ]; then
  "$REPO_ROOT/.cursor/hooks/_flush_events.sh" "$RUN_ID" || true
fi

# Always exit 0 — logging must never break the agent run (failClosed: false).
exit 0
