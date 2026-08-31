#!/usr/bin/env bash
# wait_job_run.sh — parent-session wait with ≤60s heartbeats (task_key + state).
#
# Usage:
#   ./agents/tools/wait_job_run.sh --bundle-run          # start medallion + wait
#   ./agents/tools/wait_job_run.sh --run-id 123456789     # poll an existing run
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

edw_run_id() {
  if [ -f "${REPO_ROOT}/agents/out/CURRENT_RUN" ]; then
    tr -d '[:space:]' < "${REPO_ROOT}/agents/out/CURRENT_RUN"
  else
    echo unknown
  fi
}

emit_job_handoff() {
  local oc="$1"
  python3 "${REPO_ROOT}/agents/tools/edw_handoff.py" \
    --run-id "$(edw_run_id)" \
    --from coordinator --to job --action run     --outcome "$oc" || true
}

record_job_success() {
  local val="$1"
  local rid
  rid="$(edw_run_id)"
  if [ -z "$rid" ] || [ "$rid" = "unknown" ]; then
    return 0
  fi
  mkdir -p "${REPO_ROOT}/agents/out/${rid}"
  printf '{"job_success": %s}\n' "$val" > "${REPO_ROOT}/agents/out/${rid}/job_success.json"
  python3 "${REPO_ROOT}/agents/tools/mlflow_observe.py" metric \
    --run-id "$rid" --key job_success --value "$val" || true
}

INTERVAL="${WAIT_JOB_HEARTBEAT_SEC:-60}"
JOB_RUN_ID=""
BUNDLE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) JOB_RUN_ID="$2"; shift 2 ;;
    --bundle-run) BUNDLE=1; shift ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    -h|--help)
      sed -n '1,10p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

print_heartbeat() {
  local rid="$1"
  local json
  json="$("$DBX" jobs get-run --run-id "$rid" -o json 2>/dev/null || true)"
  if [ -z "$json" ]; then
    echo "[wait_job_run] run_id=${rid} (get-run failed)"
    return
  fi
  python3 - "$json" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
state = ((d.get("state") or {}).get("life_cycle_state")
         or (d.get("status") or {}).get("state") or "?")
result = ((d.get("state") or {}).get("result_state") or "")
print(f"[wait_job_run] life_cycle={state} result={result}")
tasks = d.get("tasks") or d.get("job_clusters") or []
# tasks may be under tasks with state
for t in d.get("tasks") or []:
    key = t.get("task_key") or "?"
    st = ((t.get("state") or {}).get("life_cycle_state") or "?")
    rs = ((t.get("state") or {}).get("result_state") or "")
    print(f"[wait_job_run]   task_key={key} state={st} {rs}".rstrip())
PY
}

life_of() {
  "$DBX" jobs get-run --run-id "$1" -o json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
print((d.get("state") or {}).get("life_cycle_state") or "")
' || true
}

if [ "$BUNDLE" -eq 1 ]; then
  "${REPO_ROOT}/agents/tools/wake_sources.sh"
  "${REPO_ROOT}/agents/tools/assert_no_running_jobs.sh"
  echo "[wait_job_run] starting bundle run edw_migration_medallion"
  # bundle run is blocking; poll in background for heartbeats
  HEART_PID=""
  (
    sleep 15
    while true; do
      RID="$("$DBX" jobs list-runs --active-only -o json 2>/dev/null | python3 -c '
import json,sys
raw=sys.stdin.read().strip() or "[]"
try:
    d=json.loads(raw)
except Exception:
    d=[]
runs=d if isinstance(d,list) else (d.get("runs") or [])
print(runs[0].get("run_id","") if runs else "")
' || true)"
      if [ -n "${RID:-}" ]; then
        print_heartbeat "$RID"
      else
        echo "[wait_job_run] (no active run listed yet)"
      fi
      sleep "$INTERVAL"
    done
  ) &
  HEART_PID=$!
  trap 'kill "$HEART_PID" 2>/dev/null || true' EXIT
  set +e
  "$DBX" bundle run edw_migration_medallion -t dev
  RC=$?
  set -e
  kill "$HEART_PID" 2>/dev/null || true
  wait "$HEART_PID" 2>/dev/null || true
  trap - EXIT
  if [ "$RC" -ne 0 ]; then
    echo "[wait_job_run] bundle run FAILED exit=${RC}" >&2
    record_job_success 0
    emit_job_handoff fail
    exit "$RC"
  fi
  echo "[wait_job_run] bundle run SUCCESS"
  record_job_success 1
  emit_job_handoff ok
  exit 0
fi

: "${JOB_RUN_ID:?--run-id (Databricks job run id) required unless --bundle-run}"
while true; do
  ST="$(life_of "$JOB_RUN_ID")"
  print_heartbeat "$JOB_RUN_ID"
  case "$ST" in
    TERMINATED|SKIPPED|INTERNAL_ERROR|"")
      if [ "$ST" = "TERMINATED" ]; then
        RES="$("$DBX" jobs get-run --run-id "$JOB_RUN_ID" -o json | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("state") or {}).get("result_state") or "")')"
        if [ "$RES" = "SUCCESS" ]; then
          echo "[wait_job_run] SUCCESS"
          record_job_success 1
          emit_job_handoff ok
          exit 0
        fi
        echo "[wait_job_run] FAILED result=${RES}" >&2
        record_job_success 0
        emit_job_handoff fail
        exit 1
      fi
      if [ -z "$ST" ]; then
        echo "[wait_job_run] could not read run state" >&2
        record_job_success 0
        emit_job_handoff fail
        exit 1
      fi
      echo "[wait_job_run] ended state=${ST}" >&2
      record_job_success 0
      emit_job_handoff fail
      exit 1
      ;;
  esac
  sleep "$INTERVAL"
done
