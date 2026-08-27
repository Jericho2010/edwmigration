#!/usr/bin/env bash
# assert_no_running_jobs.sh — Free Edition is 5 tasks per *account*.
# Abort before make run if another job run is already RUNNING.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi
# shellcheck disable=SC1091
. "${REPO_ROOT}/agents/tools/apply_databricks_cli_auth.sh"

DBX="${REPO_ROOT}/agents/tools/databricks_cli.sh"
JSON="$("$DBX" jobs list-runs --active-only -o json 2>/dev/null || echo '[]')"
COUNT="$(printf '%s' "$JSON" | python3 -c '
import json,sys
raw=sys.stdin.read().strip() or "[]"
try:
    d=json.loads(raw)
except Exception:
    d=[]
runs=d if isinstance(d,list) else (d.get("runs") or [])
print(len(runs))
')"
if [ "${COUNT:-0}" -gt 0 ]; then
  echo "[assert_no_running_jobs] FAIL: ${COUNT} active job run(s) — Free Edition shares a 5-task account cap" >&2
  printf '%s\n' "$JSON" | python3 -c '
import json,sys
raw=sys.stdin.read().strip() or "[]"
try:
    d=json.loads(raw)
except Exception:
    d=[]
runs=d if isinstance(d,list) else (d.get("runs") or [])
for r in runs:
    print("  run_id=%s job=%s state=%s" % (
        r.get("run_id"),
        (r.get("job_id") or (r.get("run_name") or "")),
        ((r.get("state") or {}).get("life_cycle_state") or ""),
    ))
' >&2
  exit 1
fi
echo "[assert_no_running_jobs] OK no other RUNNING job"
