#!/usr/bin/env bash
# launch_convert_wave.sh — lock a Convert wave (≤5), dual_write start, print Task contract.
#
# Coordinator must not launch Convert without convert_wave.json from this script.
#
# Usage:
#   ./agents/tools/launch_convert_wave.sh --run-id UUID --item-id item-001 --item-id item-002
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

RUN_ID=""
ITEM_IDS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2 ;;
    --item-id) ITEM_IDS+=("$2"); shift 2 ;;
    -h|--help)
      sed -n '1,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

: "${RUN_ID:?--run-id required}"
if [ "${#ITEM_IDS[@]}" -eq 0 ]; then
  echo "[launch_convert_wave] ERROR: pass at least one --item-id" >&2
  exit 1
fi
if [ "${#ITEM_IDS[@]}" -gt 5 ]; then
  echo "[launch_convert_wave] ERROR: wave size ${#ITEM_IDS[@]} exceeds 5" >&2
  exit 1
fi

OUT="${REPO_ROOT}/agents/out/${RUN_ID}"
BACKLOG="${OUT}/migration_backlog.json"
if [ ! -f "$BACKLOG" ]; then
  echo "[launch_convert_wave] ERROR: missing $BACKLOG" >&2
  exit 1
fi

PY="$("${REPO_ROOT}/agents/tools/resolve_python.sh")"
WAVE_JSON="$("$PY" - "$BACKLOG" "${ITEM_IDS[@]}" <<'PY'
import json, sys
from pathlib import Path
backlog_path = Path(sys.argv[1])
wanted = sys.argv[2:]
backlog = json.loads(backlog_path.read_text())
by_id = {str(i.get("item_id")): i for i in backlog}
missing = [i for i in wanted if i not in by_id]
if missing:
    raise SystemExit("unknown item_id(s): " + ",".join(missing))
paths = []
items = []
for iid in wanted:
    it = by_id[iid]
    tp = it.get("target_path") or ""
    paths.append(tp)
    items.append({"item_id": iid, "target_path": tp, "legacy_proc": it.get("legacy_proc")})
print(json.dumps({"item_ids": wanted, "target_paths": paths, "items": items}, indent=2))
PY
)"

mkdir -p "$OUT"
printf '%s\n' "$WAVE_JSON" > "${OUT}/convert_wave.json"

while IFS= read -r iid; do
  [ -z "$iid" ] && continue
  ARTIFACT="$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1]));
print(next((i["target_path"] for i in d["items"] if i["item_id"]==sys.argv[2]),""))' \
    "${OUT}/convert_wave.json" "$iid")"
  "${REPO_ROOT}/agents/tools/dual_write_agent_lifecycle.sh" \
    --run-id "$RUN_ID" --agent convert --phase start --item-id "$iid" \
    --detail "{\"from\":\"coordinator\",\"to\":\"convert\",\"item_id\":\"${iid}\",\"action\":\"launch\",\"artifact\":\"${ARTIFACT}\",\"outcome\":\"ok\"}"
done < <(printf '%s\n' "${ITEM_IDS[@]}")

echo "[launch_convert_wave] wrote ${OUT}/convert_wave.json items=${#ITEM_IDS[@]}"
echo "[launch_convert_wave] Task contract (required subagent_type):"
for iid in "${ITEM_IDS[@]}"; do
  echo "  Task subagent_type=edw-convert item_id=${iid}  (dual_write start already issued)"
done
echo "[launch_convert_wave] After JSON appears: dual_write --phase stop --item-id <id>; then merge_convert_results.py"
