#!/usr/bin/env bash
# on_subagent_stop.sh — Cursor subagentStop hook (array hooks.json, version 1).
# Emits followup_message only when status=completed, agent=gate, gate=fail,
# and attempt/loop_count under max_retries.
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$("${HOOK_DIR}/_repo_root.sh")"
if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

PAYLOAD="$(cat || true)"
RUN_ID="$("${HOOK_DIR}/_resolve_run_id.sh" "$REPO_ROOT")"
AGENT="$("${HOOK_DIR}/_map_agent.sh" "$PAYLOAD")"

"${HOOK_DIR}/_flush_events.sh" "$RUN_ID" || true

eval "$(python3 - "$PAYLOAD" <<'PY'
import json, sys, shlex
try:
    o = json.loads(sys.argv[1] if len(sys.argv)>1 else "{}")
except Exception:
    o = {}
print(f"STATUS={shlex.quote(str(o.get('status') or 'completed'))}")
print(f"LOOP_COUNT={shlex.quote(str(o.get('loop_count') or 0))}")
PY
)"

if [ "$AGENT" != "gate" ] || [ "$STATUS" != "completed" ]; then
  echo '{}'
  exit 0
fi

MANIFEST_FILE="${REPO_ROOT}/agents/out/${RUN_ID}/migration_manifest.json"
CONTEXT_FILE="${REPO_ROOT}/agents/out/${RUN_ID}/context.json"

if [ ! -s "$MANIFEST_FILE" ]; then
  echo '{}'
  exit 0
fi

python3 - "$MANIFEST_FILE" "$CONTEXT_FILE" "$LOOP_COUNT" <<'PY'
import json, sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
ctx_path = Path(sys.argv[2])
loop_count = int(sys.argv[3])
ctx = json.loads(ctx_path.read_text()) if ctx_path.is_file() else {"max_retries": 2, "attempt": 0}

gate = manifest.get("gate", "fail")
attempt = int(manifest.get("attempt", ctx.get("attempt", 0)))
max_retries = int(ctx.get("max_retries", 2))

if gate == "pass":
    print("{}")
    raise SystemExit(0)

if gate == "fail" and attempt < max_retries and loop_count < max_retries:
    blockers = "; ".join(b.get("message", "") for b in manifest.get("blockers", []))
    next_attempt = attempt + 1
    ctx["attempt"] = next_attempt
    if ctx_path.is_file():
        ctx_path.write_text(json.dumps(ctx, indent=2) + "\n")
    msg = (
        f"Retry convert (attempt {next_attempt}/{max_retries}): {blockers}. "
        "Re-delegate edw-convert for blocked backlog items, then edw-test and edw-gate."
    )
    print(json.dumps({"followup_message": msg}))
else:
    print("{}")
PY
exit 0
