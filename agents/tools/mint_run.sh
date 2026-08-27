#!/usr/bin/env bash
# mint_run.sh — write CURRENT_RUN + context.json + MLflow init + nest-probe (Track A).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

TRACK_A=0
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --track-a) TRACK_A=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) echo "Usage: $0 [--track-a] [--force]"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

CURRENT="${REPO_ROOT}/agents/out/CURRENT_RUN"
if [ -f "$CURRENT" ] && [ "$FORCE" -eq 0 ]; then
  RID="$(tr -d '[:space:]' < "$CURRENT")"
  echo "[mint_run] CURRENT_RUN already ${RID} — adopting (no second UUID)"
else
  RID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  mkdir -p "${REPO_ROOT}/agents/out/${RID}"
  printf '%s\n' "$RID" > "$CURRENT"
  echo "[mint_run] minted ${RID}"
fi

mkdir -p "${REPO_ROOT}/agents/out/${RID}"
CTX="${REPO_ROOT}/agents/out/${RID}/context.json"
if [ ! -f "$CTX" ]; then
  python3 - "$CTX" "$RID" <<'PY'
import json, os, sys
from pathlib import Path
path, run_id = Path(sys.argv[1]), sys.argv[2]
doc = {
  "run_id": run_id,
  "source_type": os.environ.get("SOURCE_TYPE", "sqlserver"),
  "source_database": os.environ.get("SOURCE_DATABASE") or os.environ.get("AZ_SQL_DB") or "",
  "uc_catalog": os.environ.get("DATABRICKS_CATALOG", "edw_migration"),
  "foreign_catalog": os.environ.get("FOREIGN_CATALOG", "sqlserver_fed"),
  "databricks_host": os.environ.get("DATABRICKS_HOST", ""),
  "max_retries": 2,
  "attempt": 0,
  "routines_skipped_reason": None,
  "demo_mode": False,
  "track_a": False,
}
path.write_text(json.dumps(doc, indent=2) + "\n")
PY
  echo "[mint_run] wrote ${CTX}"
fi
if [ "$TRACK_A" -eq 1 ]; then
  python3 - "$CTX" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
doc = json.loads(p.read_text()) if p.is_file() else {}
doc["track_a"] = True
doc["demo_mode"] = True
p.write_text(json.dumps(doc, indent=2) + "\n")
PY
fi

PY="$("${REPO_ROOT}/agents/tools/resolve_python.sh")"
"$PY" "${REPO_ROOT}/agents/tools/mlflow_observe.py" init --run-id "$RID"
if [ "$TRACK_A" -eq 1 ]; then
  if ! "$PY" "${REPO_ROOT}/agents/tools/mlflow_observe.py" nest-probe --run-id "$RID"; then
    echo "[mint_run] nest-probe FAIL — stop Track A (do not Discover with a lying tree)" >&2
    exit 1
  fi
  "$PY" "${REPO_ROOT}/agents/tools/mlflow_observe.py" span-start \
    --run-id "$RID" --key "subagent:demo-guide:${RID}" --name "agent.demo_guide" \
    --kind agent --agent demo-guide --detail '{"from":"start","to":"demo-guide","action":"provision","outcome":"ok"}' || true
fi
echo "[mint_run] run_id=${RID}"
