#!/usr/bin/env bash
# observe_status.sh — Paste-friendly observability snapshot for demo checkpoints.
# Usage:
#   ./agents/tools/observe_status.sh
#   ./agents/tools/observe_status.sh --run-id UUID
#   ./agents/tools/observe_status.sh --stage Assess
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

STAGE=""
RUN_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --stage) STAGE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--run-id UUID] [--stage Name]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$RUN_ID" ] && [ -f "${REPO_ROOT}/agents/out/CURRENT_RUN" ]; then
  RUN_ID="$(tr -d '[:space:]' < "${REPO_ROOT}/agents/out/CURRENT_RUN")"
fi

: "${DATABRICKS_CATALOG:=edw_migration}"
CATALOG="$DATABRICKS_CATALOG"

echo
echo "=== observe_status${STAGE:+ · ${STAGE}} ==="
echo "Open these now (live during the run): Control Plane + Genie + Catalog + Job + Notebooks + MLflow observe_url below."
if [ -n "$RUN_ID" ]; then
  echo "run_id=${RUN_ID}"
else
  echo "run_id=(none — no CURRENT_RUN)"
fi
echo "catalog=${CATALOG}"

if [ -n "${DATABRICKS_HOST:-}" ] && [ -n "${DATABRICKS_WAREHOUSE_ID:-}" ]; then
  COUNTS="$("${REPO_ROOT}/agents/tools/run_sql.sh" --sql "
SELECT 'agent_events' AS t, COUNT(*) AS n FROM ${CATALOG}.ops.agent_events
UNION ALL SELECT 'migration_inventory', COUNT(*) FROM ${CATALOG}.ops.migration_inventory
UNION ALL SELECT 'migration_backlog', COUNT(*) FROM ${CATALOG}.ops.migration_backlog
UNION ALL SELECT 'reconcile_results', COUNT(*) FROM ${CATALOG}.ops.reconcile_results
UNION ALL SELECT 'migration_manifest_current', COUNT(*) FROM ${CATALOG}.ops.migration_manifest_current
UNION ALL SELECT 'proc_conversion_map', COUNT(*) FROM ${CATALOG}.ops.proc_conversion_map
UNION ALL SELECT 'load_control', COUNT(*) FROM ${CATALOG}.ops.load_control
" 2>/dev/null || true)"
  echo "ops counts:"
  if [ -n "$COUNTS" ]; then
    echo "$COUNTS" | awk -F'\t' 'NR==1 && $1=="t" {next} NF>=2 {printf "  %-28s %s\n", $1, $2}'
  else
    echo "  (query failed — warehouse/auth?)"
  fi

  if [ -n "$RUN_ID" ]; then
    EV="$("${REPO_ROOT}/agents/tools/run_sql.sh" --sql "
SELECT agent, event, LEFT(COALESCE(detail,''), 120) AS detail
FROM ${CATALOG}.ops.agent_events
WHERE run_id = '${RUN_ID}'
ORDER BY ts DESC
LIMIT 8;
" 2>/dev/null || true)"
    echo "recent agent_events for run:"
    if [ -n "$EV" ]; then
      echo "$EV" | awk -F'\t' 'NR==1 && $1=="agent" {next} {print "  "$0}'
    else
      echo "  (none yet)"
    fi
    HO="$("${REPO_ROOT}/agents/tools/run_sql.sh" --sql "
SELECT LEFT(COALESCE(detail,''), 400) AS detail
FROM ${CATALOG}.ops.agent_events
WHERE run_id = '${RUN_ID}' AND lower(event) = 'handoff'
ORDER BY ts DESC
LIMIT 5;
" 2>/dev/null || true)"
    echo "last handoffs:"
    if [ -n "$HO" ]; then
      python3 - "$HO" <<'PY' 2>/dev/null || echo "$HO" | awk -F'\t' 'NR==1 && $1=="detail" {next} {print "  "$0}'
import json, sys
raw = sys.argv[1]
for line in raw.splitlines():
    line=line.strip()
    if not line or line=="detail":
        continue
    try:
        d=json.loads(line)
        src=d.get("from","?"); dst=d.get("to","?")
        item=d.get("item_id") or ""
        oc=d.get("outcome") or ""
        extra=f" ({item})" if item else ""
        print(f"  {src} → {dst}{extra} {oc}".rstrip())
    except Exception:
        print("  "+line[:120])
PY
    else
      echo "  (none yet)"
    fi
    MAP="$("${REPO_ROOT}/agents/tools/run_sql.sh" --sql "
SELECT status, COUNT(*) AS n FROM ${CATALOG}.ops.proc_conversion_map
WHERE run_id = '${RUN_ID}' GROUP BY status
" 2>/dev/null || true)"
    echo "convert map:"
    if [ -n "$MAP" ]; then
      echo "$MAP" | awk -F'\t' 'NR==1 && $1=="status" {next} {print "  "$0}'
    else
      echo "  (none yet)"
    fi
  fi
else
  echo "ops counts: skipped (DATABRICKS_HOST / WAREHOUSE_ID unset)"
fi

# Local artifacts
if [ -n "$RUN_ID" ]; then
  OUT="${REPO_ROOT}/agents/out/${RUN_ID}"
  echo "local artifacts:"
  for f in inventory.json migration_backlog.json convert_summary.json reconcile_report.json migration_manifest.json mlflow_context.json notebooks.json; do
    if [ -f "${OUT}/${f}" ]; then
      echo "  OK  ${f}"
    else
      echo "  --  ${f}"
    fi
  done
  BUF="${OUT}/events.buf.jsonl"
  if [ -f "$BUF" ]; then
    echo "  buf events.buf.jsonl lines=$(wc -l < "$BUF" | tr -d ' ')"
  fi
fi

# URLs (best-effort)
echo "--- URLs ---"
"${REPO_ROOT}/agents/tools/print_observability_urls.sh" 2>/dev/null | sed -n '/^=== Observability ===/,/^=====/{p}' || true

# MLflow context hint
if [ -n "$RUN_ID" ] && [ -f "${REPO_ROOT}/agents/out/${RUN_ID}/mlflow_context.json" ]; then
  python3 - "$RUN_ID" <<'PY' 2>/dev/null || true
import json, sys
from pathlib import Path
run_id = sys.argv[1]
p = Path(f"agents/out/{run_id}/mlflow_context.json")
d = json.loads(p.read_text())
print(f"mlflow enabled={d.get('enabled')} last_error={d.get('last_error') or d.get('error') or ''}")
url = (d.get("observe_url") or "").strip()
if url:
    print(f"observe_url: {url}")
err = (d.get("last_error") or d.get("error") or "").strip()
if err:
    print("FAIL last_error set — stop Track A / Convert until nest-probe + serve are healthy")
PY
fi

if [ -n "$RUN_ID" ] && [ -f "${REPO_ROOT}/agents/out/${RUN_ID}/sod_violation" ]; then
  echo "FAIL sod_violation present — coordinator wrote silver/gold or convert missed wave lock"
  cat "${REPO_ROOT}/agents/out/${RUN_ID}/sod_violation"
fi

echo "Note: Gate Hero (gate counters) stays empty until Gate writes migration_manifest_current."
echo "Note: Tables-landed (load_control) should move at Land. Latest-run widgets prefer agent_events then manifest."
echo "Note: Inventory/Events/Backlog should move as stages complete — empty during a run means hooks/edw-* missing or need make reset-sink."
echo "===================="
echo
