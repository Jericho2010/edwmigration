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

: "${DATABRICKS_HOST:?DATABRICKS_HOST required}"
HOST="${DATABRICKS_HOST%/}"
SEARCH_HINT="EDW Migration Control Plane"

echo
echo "=== Observability ==="

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
  echo "Control Plane: open Databricks → Dashboards → search '${SEARCH_HINT}'"
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
  echo "Genie: run make genie (or search Genie for EDW Migration Copilot)"
fi

echo "Trust checklist: inventory.json → bronze reconcile pass → Gate blockers empty"
echo "================="
echo
