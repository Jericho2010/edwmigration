#!/usr/bin/env bash
# Self-check: provision guard stamps standalone announce and kicks on stop.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="${ROOT}/.cursor/hooks/on_provision_guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export EDW_PROVISION_GUARD_STAMP="${TMP}/stamp"
export EDW_PROVISION_GUARD_MAX_AGE_SEC=1800
export EDW_PROVISION_GUARD_RUNNING=0

fail() { echo "FAIL: $*" >&2; exit 1; }

out="$(echo '{"command":"./agents/tools/announce_observability.sh --stage Provision"}' | "$HOOK" after-shell)"
[[ -f "$EDW_PROVISION_GUARD_STAMP" ]] || fail "announce should write stamp"
echo "$out" | grep -q 'additional_context' || fail "announce should return additional_context: $out"
echo "$out" | grep -q 'track_a_provision.sh' || fail "kick should name track_a_provision.sh: $out"

out="$(echo '{"command":"DATABRICKS_CATALOG=edw_migration ./agents/tools/track_a_provision.sh"}' | "$HOOK" after-shell)"
[[ ! -f "$EDW_PROVISION_GUARD_STAMP" ]] || fail "wrapper should clear stamp"
echo "$out" | grep -qx '{}' || fail "wrapper after-shell should be {}: $out"

echo '{"command":"./agents/tools/announce_observability.sh --stage Provision"}' | "$HOOK" after-shell >/dev/null
out="$(echo '{}' | "$HOOK" stop)"
echo "$out" | grep -q 'followup_message' || fail "stop with fresh stamp should kick: $out"

rm -f "$EDW_PROVISION_GUARD_STAMP"
out="$(echo '{}' | "$HOOK" stop)"
echo "$out" | grep -qx '{}' || fail "stop without stamp should be {}: $out"

echo '{"command":"./agents/tools/announce_observability.sh --stage Provision"}' | "$HOOK" after-shell >/dev/null
EDW_PROVISION_GUARD_RUNNING=1
out="$(echo '{}' | "$HOOK" stop)"
echo "$out" | grep -qx '{}' || fail "stop while provision running should be {}: $out"
EDW_PROVISION_GUARD_RUNNING=0

echo '{"command":"./agents/tools/announce_observability.sh --stage Provision"}' | "$HOOK" after-shell >/dev/null
python3 - "$EDW_PROVISION_GUARD_STAMP" <<'PY'
import os, sys, time
from pathlib import Path
p = Path(sys.argv[1])
os.utime(p, (time.time() - 4000, time.time() - 4000))
PY
out="$(echo '{}' | "$HOOK" stop)"
echo "$out" | grep -qx '{}' || fail "stop with stale stamp should be {}: $out"

rm -f "$EDW_PROVISION_GUARD_STAMP"
echo '{"command":"./agents/tools/announce_observability.sh --stage Setup"}' | "$HOOK" after-shell >/dev/null
[[ ! -f "$EDW_PROVISION_GUARD_STAMP" ]] || fail "Setup announce should not stamp"

echo '{"command":"./agents/tools/announce_observability.sh --stage Provision && ./agents/tools/track_a_provision.sh"}' | "$HOOK" after-shell >/dev/null
[[ ! -f "$EDW_PROVISION_GUARD_STAMP" ]] || fail "combined announce+wrapper should not stamp"

echo "OK provision guard self-check"
