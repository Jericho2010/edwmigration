#!/usr/bin/env bash
# on_subagent_stop.sh — Cursor hook fired when a subagent finishes.
#
# Wired in .cursor/hooks.json for: subagentStop.
# failClosed: true — retry enforcement must succeed or the run aborts.
#
# Responsibilities:
#   1. Flush the buffered agent events for this run_id to ops.agent_events.
#   2. If the subagent that just stopped was the Gate agent, read the
#      migration_manifest.json from disk and decide whether to re-delegate
#      to Convert (retry) or stop.
#
# Hook payload (JSON on stdin): { agent, event: "subagentStop", run_id, ... }
# NOTE: the payload does NOT include file contents. We read artifacts from
# disk at agents/out/<run_id>/.
#
# Retry budget: max_retries is read from agents/out/<run_id>/context.json
# so loop_limit and max_retries stay aligned (no drift between two sources).
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Load .env
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

# ---------------------------------------------------------------------------
# Read hook payload
# ---------------------------------------------------------------------------
PAYLOAD="$(cat || true)"

if command -v jq >/dev/null 2>&1; then
  RUN_ID="$(echo "$PAYLOAD" | jq -r '.run_id // "unknown"')"
  AGENT="$(echo "$PAYLOAD" | jq -r '.agent // "coordinator"')"
else
  RUN_ID="$(echo "$PAYLOAD" | sed -n 's/.*"run_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  AGENT="$(echo "$PAYLOAD"  | sed -n 's/.*"agent"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -z "$RUN_ID" ] && RUN_ID="unknown"
  [ -z "$AGENT" ]  && AGENT="coordinator"
fi

# ---------------------------------------------------------------------------
# 1. Final flush of buffered events
# ---------------------------------------------------------------------------
"${REPO_ROOT}/.cursor/hooks/_flush_events.sh" "$RUN_ID" || true

# ---------------------------------------------------------------------------
# 2. Retry decision (only when the Gate subagent stops)
# ---------------------------------------------------------------------------
if [ "$AGENT" != "gate" ]; then
  exit 0
fi

CONTEXT_FILE="${REPO_ROOT}/agents/out/${RUN_ID}/context.json"
MANIFEST_FILE="${REPO_ROOT}/agents/out/${RUN_ID}/migration_manifest.json"

if [ ! -s "$MANIFEST_FILE" ]; then
  echo "[on_subagent_stop] gate stopped but no migration_manifest.json found at ${MANIFEST_FILE}" >&2
  echo "[on_subagent_stop] treating as gate=fail with no retries (manifest missing)." >&2
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[on_subagent_stop] jq required for retry decision; not retrying." >&2
  exit 0
fi

GATE="$(jq -r '.gate' "$MANIFEST_FILE")"
ATTEMPT="$(jq -r '.attempt // 0' "$MANIFEST_FILE")"

# Read max_retries from context.json (single source of truth — no loop_limit drift)
if [ -s "$CONTEXT_FILE" ]; then
  MAX_RETRIES="$(jq -r '.max_retries // 2' "$CONTEXT_FILE")"
else
  MAX_RETRIES=2
fi

if [ "$GATE" = "pass" ]; then
  echo "[on_subagent_stop] gate=pass; run complete." >&2
  exit 0
fi

if [ "$GATE" != "fail" ]; then
  echo "[on_subagent_stop] unexpected gate value: ${GATE}; not retrying." >&2
  exit 0
fi

# gate=fail
if [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; then
  BLOCKERS="$(jq -r '.blockers | map(.message) | join("; ")' "$MANIFEST_FILE")"
  # Emit a followup_message that the coordinator reads as a re-delegation
  # instruction. The coordinator increments attempt in context.json itself.
  jq -n \
    --arg b "$BLOCKERS" \
    --arg r "$RUN_ID" \
    --argjson a "$ATTEMPT" \
    --argjson m "$MAX_RETRIES" \
    '{
      followup_message: ("Retry convert (attempt " + ($a+1|tostring) + "/" + ($m|tostring) + "): " + $b),
      run_id: $r,
      action: "redelegate_convert",
      attempt: ($a + 1),
      max_retries: $m
    }'
  exit 0
fi

# Retries exhausted
echo "[on_subagent_stop] gate=fail and retries exhausted (attempt=${ATTEMPT}, max=${MAX_RETRIES}); stopping." >&2
exit 0
