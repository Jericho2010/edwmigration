#!/usr/bin/env bash
# Print Control Plane dashboard URL + Genie room URL (best-effort, never fails setup).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "${REPO_ROOT}/.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    key="${line%%=*}"
    val="${line#*=}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    [ -n "$key" ] || continue
    if [ -z "${!key+x}" ]; then
      export "$key=$val"
    fi
  done < "${REPO_ROOT}/.env"
fi

SEARCH_HINT="EDW Migration Control Plane"

if command -v python3 >/dev/null 2>&1 && [ -f "${REPO_ROOT}/agents/tools/databricks_cli_env.py" ]; then
  eval "$(python3 "${REPO_ROOT}/agents/tools/databricks_cli_env.py" --export 2>/dev/null || true)"
fi

echo
echo "=== Observability ==="
echo "Keep these open during the run."

if [ -z "${DATABRICKS_HOST:-}" ]; then
  echo "Control Plane: not ready yet — appears after make setup (deploy + genie)."
  echo "Genie: not ready yet — appears after make setup."
  echo "Catalog: not ready yet — appears after make setup."
  echo "Job: not ready yet — appears after make deploy."
  echo "Notebooks: appear after Land (publish_run_notebooks)."
  echo "MLflow traces: appear after mint (mlflow_observe init / ensure_run_events)."
  echo "Until then: watch chat for [edw] heartbeats (track_a_provision / bootstrap)."
  echo "================="
  echo
  exit 0
fi

HOST="${DATABRICKS_HOST%/}"

DASH_ID=""
DASH_LABEL=""
if command -v databricks >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  DASH_JSON="$(databricks lakeview list -o json 2>/dev/null || echo '{}')"
  PARSE_FILE="$(mktemp)"
  printf '%s' "$DASH_JSON" >"${PARSE_FILE}.in"
  python3 - "${PARSE_FILE}.in" "${PARSE_FILE}" <<'PY' || true
import json, sys
from pathlib import Path
raw = Path(sys.argv[1]).read_text().strip() or "{}"
try:
    data = json.loads(raw)
except Exception:
    data = {}
rows = data.get("dashboards", data) if isinstance(data, dict) else data
if not isinstance(rows, list):
    rows = []
ranked = []
for r in rows:
    name = r.get("display_name") or r.get("name") or ""
    did = r.get("dashboard_id") or r.get("id") or ""
    if not did:
        continue
    lname = name.lower()
    if "edw migration control plane" in lname:
        ranked.append((0, name, did))
    elif "edw migration agent events" in lname:
        ranked.append((1, name, did))
    elif "edw migration" in lname:
        ranked.append((2, name, did))
ranked.sort(key=lambda x: x[0])
out = Path(sys.argv[2])
if ranked:
    out.write_text(f"{ranked[0][1]}\n{ranked[0][2]}\n")
else:
    out.write_text("")
PY
  if [ -s "$PARSE_FILE" ]; then
    DASH_LABEL="$(sed -n '1p' "$PARSE_FILE")"
    DASH_ID="$(sed -n '2p' "$PARSE_FILE")"
  fi
  rm -f "$PARSE_FILE" "${PARSE_FILE}.in"
fi

if [ -n "${DASH_ID:-}" ]; then
  echo "Control Plane: ${HOST}/dashboardsv3/${DASH_ID}"
  echo "  name: ${DASH_LABEL}"
else
  echo "Control Plane: not ready yet — open Databricks → Dashboards → search '${SEARCH_HINT}' after make setup"
  echo "  (deploy may still be propagating; re-run: make print-urls)"
fi

GENIE_ID=""
if command -v databricks >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  GENIE_ID="$(
    databricks api get /api/2.0/genie/spaces 2>/dev/null \
      | jq -r '.spaces // [] | map(select(.title|test("EDW Migration"))) | .[0].space_id // empty' \
      2>/dev/null || true
  )"
fi
if [ -n "${GENIE_ID:-}" ]; then
  echo "Genie: ${HOST}/genie/rooms/${GENIE_ID}"
else
  echo "Genie: not ready yet — run make genie (or search Genie for EDW Migration Copilot) after make setup"
fi

CATALOG="${DATABRICKS_CATALOG:-edw_migration}"
echo "Catalog: ${HOST}/explore/data/${CATALOG}"

CURRENT_FILE="${REPO_ROOT}/agents/out/CURRENT_RUN"
RUN_ID=""
if [ -f "$CURRENT_FILE" ]; then
  RUN_ID="$(tr -d '[:space:]' < "$CURRENT_FILE")"
fi
NB_FILE=""
if [ -n "$RUN_ID" ] && [ -f "${REPO_ROOT}/agents/out/${RUN_ID}/notebooks.json" ]; then
  NB_FILE="${REPO_ROOT}/agents/out/${RUN_ID}/notebooks.json"
fi
NB_URL=""
JOB_URL=""
JOB_ID=""
if [ -n "$NB_FILE" ] && command -v python3 >/dev/null 2>&1; then
  eval "$(python3 - "$NB_FILE" <<'PY' || true
import json, shlex, sys
from pathlib import Path
d = {}
try:
    d = json.loads(Path(sys.argv[1]).read_text())
except Exception:
    pass
print(f"NB_URL={shlex.quote(str(d.get('folder_url') or '').strip())}")
print(f"JOB_URL={shlex.quote(str(d.get('job_url') or '').strip())}")
print(f"JOB_ID={shlex.quote(str(d.get('job_id') or '').strip())}")
PY
)"
fi
if [ -z "${JOB_ID:-}" ] && command -v databricks >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  JOBS_FILE="$(mktemp)"
  databricks jobs list -o json >"$JOBS_FILE" 2>/dev/null || echo '{}' >"$JOBS_FILE"
  JOB_ID="$(python3 - "$JOBS_FILE" "${REPO_ROOT}/agents/tools" <<'PY' 2>/dev/null || true
import json, sys
from pathlib import Path
sys.path.insert(0, sys.argv[2])
import publish_run_notebooks as p
raw = Path(sys.argv[1]).read_text().strip() or "{}"
try:
    data = json.loads(raw)
except Exception:
    data = {}
print(p.find_medallion_job_id(data))
PY
)"
  rm -f "$JOBS_FILE"
  if [ -n "${JOB_ID:-}" ]; then
    JOB_URL="${HOST}/jobs/${JOB_ID}"
  fi
fi
if [ -n "${NB_URL:-}" ]; then
  echo "Notebooks: ${NB_URL}"
else
  echo "Notebooks: appear after Land (python3 agents/tools/publish_run_notebooks.py --run-id <id>)"
fi
if [ -n "${JOB_URL:-}" ]; then
  echo "Job: ${JOB_URL}"
else
  echo "Job: appears after make deploy"
fi

echo "Trust checklist: inventory.json → bronze reconcile pass → Gate blockers empty"

# MLflow observe_url (additive live traces; soft)
OBSERVE_URL=""
if [ -n "${RUN_ID:-}" ]; then
  CTX_FILE="${REPO_ROOT}/agents/out/${RUN_ID}/mlflow_context.json"
  if [ -f "$CTX_FILE" ] && command -v python3 >/dev/null 2>&1; then
    OBSERVE_URL="$(python3 - "$CTX_FILE" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
try:
    d = json.loads(p.read_text())
except Exception:
    d = {}
print((d.get("observe_url") or "").strip())
PY
)"
  fi
  if [ -z "${OBSERVE_URL:-}" ] && [ -f "${REPO_ROOT}/agents/tools/mlflow_observe.py" ]; then
    PY="$("${REPO_ROOT}/agents/tools/resolve_python.sh" 2>/dev/null || command -v python3 || true)"
    if [ -n "${PY:-}" ]; then
      OBSERVE_URL="$("$PY" "${REPO_ROOT}/agents/tools/mlflow_observe.py" trace-url --run-id "$RUN_ID" 2>/dev/null || true)"
    fi
  fi
fi
if [ -n "${OBSERVE_URL:-}" ]; then
  echo "observe_url: ${OBSERVE_URL}"
  echo "MLflow traces: ${OBSERVE_URL}"
else
  echo "MLflow traces: run make observe-setup then re-init (mlflow_observe init / ensure_run_events)"
fi

echo "================="
echo
