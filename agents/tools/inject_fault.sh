#!/usr/bin/env bash
# inject_fault.sh — fault injection for the self-healing demo arc.
#
# Perturbs one row in edw_migration.ops.fixture_expectations so the next
# reconcile (Test stage) fails, the Gate blocks the run, and the retry hook
# fires. Revert restores the original expectation and the loop closes green.
#
# The story: legacy-side drift ("the export is stale / the business rule
# changed") is caught deterministically by reconcile + gate — nothing ships
# silently. See docs/demo-script.md "Self-healing arc".
#
# Usage:
#   ./inject_fault.sh                      # inject into default fixture
#   ./inject_fault.sh --fixture fact_sale_count --delta 1000000
#   ./inject_fault.sh --status             # show active fault, if any
#   ./inject_fault.sh --revert             # restore original expectation
#
# Env:
#   INJECT_FAULT_DRY_RUN=1   print SQL instead of executing via run_sql.sh
#
# Requires: medallion job (or stage_fixtures task) already run so
# ops.fixture_expectations is populated.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUN_SQL="${SCRIPT_DIR}/run_sql.sh"
STATE_FILE="${REPO_ROOT}/agents/out/.inject_fault.state.json"
TABLE="edw_migration.ops.fixture_expectations"
MARKER="[INJECTED-FAULT]"

FIXTURE="sample_offline_city"
DELTA="1000000"
MODE="inject"

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --fixture) FIXTURE="${2:?--fixture needs a name}"; shift 2 ;;
    --delta)   DELTA="${2:?--delta needs a number}"; shift 2 ;;
    --revert)  MODE="revert"; shift ;;
    --status)  MODE="status"; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown arg: $1" >&2; usage 1 ;;
  esac
done

run_sql() {
  if [ "${INJECT_FAULT_DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] $1"
    return 0
  fi
  "$RUN_SQL" --sql "$1" >/dev/null
}

esc() { printf '%s' "$1" | sed "s/'/''/g"; }

case "$MODE" in
  status)
    if [ -f "$STATE_FILE" ]; then
      echo "Active injected fault:"
      cat "$STATE_FILE"
      echo "Revert with: $0 --revert"
    else
      echo "No injected fault recorded (no state file at ${STATE_FILE})."
    fi
    exit 0
    ;;

  revert)
    if [ ! -f "$STATE_FILE" ]; then
      echo "Nothing to revert: no state file at ${STATE_FILE}." >&2
      exit 1
    fi
    ORIG_SQL="$(python3 - "$STATE_FILE" "$TABLE" <<'PY'
import json, sys
state, table = json.load(open(sys.argv[1])), sys.argv[2]
exp = "NULL" if state.get("expected") is None else str(int(state["expected"]))
notes = state["notes"].replace("'", "''")
print(
    f"UPDATE {table} SET expected = {exp}, compare = '{state['compare']}', "
    f"notes = '{notes}' WHERE fixture_name = '{state['fixture_name']}';"
)
PY
)"
    echo "[inject_fault] reverting fixture expectation:"
    echo "  $ORIG_SQL"
    run_sql "$ORIG_SQL"
    rm -f "$STATE_FILE"
    echo "[inject_fault] reverted. Re-run Test (reconcile) + Gate — the run should go green."
    exit 0
    ;;

  inject)
    if [ -f "$STATE_FILE" ]; then
      echo "A fault is already injected (state file exists). Revert first:" >&2
      echo "  $0 --revert" >&2
      exit 1
    fi
    if ! [[ "$DELTA" =~ ^[0-9]+$ ]]; then
      echo "--delta must be a non-negative integer, got: $DELTA" >&2
      exit 1
    fi

    # Snapshot the current row for --revert. In dry-run mode, fabricate a
    # plausible snapshot so the inject/revert cycle is testable offline.
    if [ "${INJECT_FAULT_DRY_RUN:-0}" = "1" ]; then
      SNAP='{"fixture_name":"'"$FIXTURE"'","expected":null,"compare":"gte","notes":"dry-run snapshot"}'
    else
      # ignoreNullFields=false: to_json drops null fields by default, which
      # would lose expected=NULL (the unset-expectation state we must restore).
      SNAP="$("$RUN_SQL" --sql "SELECT to_json(named_struct('fixture_name', fixture_name, 'expected', expected, 'compare', compare, 'notes', notes), map('ignoreNullFields', 'false')) AS row_json FROM ${TABLE} WHERE fixture_name = '$(esc "$FIXTURE")';" | python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(obj, dict) and "row_json" in obj:
        print(obj["row_json"])
        break
    if isinstance(obj, dict) and "fixture_name" in obj:
        print(json.dumps(obj))
        break
')"
      if [ -z "${SNAP}" ]; then
        echo "[inject_fault] ERROR: fixture '${FIXTURE}' not found in ${TABLE}." >&2
        echo "Run the medallion job (or the stage_fixtures task) first so expectations are staged." >&2
        echo "Available fixtures:" >&2
        "$RUN_SQL" --sql "SELECT fixture_name FROM ${TABLE} ORDER BY fixture_name;" >&2 || true
        exit 1
      fi
    fi

    mkdir -p "$(dirname "$STATE_FILE")"
    printf '%s\n' "$SNAP" > "$STATE_FILE"

    NEW_SQL="$(python3 - "$STATE_FILE" "$TABLE" "$DELTA" "$MARKER" <<'PY'
import json, sys
state, table, delta, marker = json.load(open(sys.argv[1])), sys.argv[2], int(sys.argv[3]), sys.argv[4]
base = state.get("expected") if state.get("expected") is not None else 0
new_expected = int(base) + delta
old_exp = "NULL" if state.get("expected") is None else str(state["expected"])
notes = f"{marker} was expected={old_exp} compare={state['compare']} | {state['notes']}"
notes = notes.replace("'", "''")
print(
    f"UPDATE {table} SET expected = {new_expected}, compare = 'gte', "
    f"notes = '{notes}' WHERE fixture_name = '{state['fixture_name']}';"
)
PY
)"
    echo "[inject_fault] injecting fault into fixture '${FIXTURE}' (expected += ${DELTA}, compare := gte):"
    echo "  $NEW_SQL"
    run_sql "$NEW_SQL"
    echo
    echo "[inject_fault] fault active. Next steps (see docs/demo-script.md 'Self-healing arc'):"
    echo "  1. Re-run the Test stage (or databricks/tests/reconcile.sql) — the fixture check fails."
    echo "  2. Re-run Gate — the run is blocked; the retry hook fires."
    echo "  3. $0 --revert, then Test + Gate again — the loop closes green."
    exit 0
    ;;
esac
