#!/usr/bin/env bash
# Record terminal scenes for README GIFs against the Azure-backed demo path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CAST_DIR="${SCRIPT_DIR}/casts"
GIF_DIR="${REPO_ROOT}/docs/img"
mkdir -p "$CAST_DIR"

if [ -f "${REPO_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${REPO_ROOT}/.env" || true
  set +a
fi

COLS=104
ROWS=28
IDLE_LIMIT=1.5
TYPE_DELAY=0.025
SAY_PAUSE=1.5

say() {
  printf '\n\033[1;36m# %s\033[0m\n' "$1"
  sleep "$SAY_PAUSE"
}

run() {
  printf '\033[1;32m$ \033[0m'
  local i
  for ((i = 0; i < ${#1}; i++)); do
    printf '%s' "${1:i:1}"
    sleep "$TYPE_DELAY"
  done
  printf '\n'
  eval "$1"
}

scene_bootstrap() {
  say "Guided demo infra: materialize env from logins, bootstrap WWI on Azure SQL free offer:"
  run "./agents/tools/materialize_demo_env.sh"
  run "make bootstrap"
}

scene_setup() {
  say "Wire Federation into the user catalog and deploy Control Plane + Genie:"
  run "make setup"
}

scene_job() {
  say "After discover/generate + Convert, run the medallion job:"
  run "databricks bundle run edw_migration_medallion -t dev"
}

scene_fault() {
  say "Inject drift — Gate should block:"
  run "./agents/tools/inject_fault.sh --fixture fact_sale_count --delta 1000000"
  run "./agents/tools/run_sql.sh --file databricks/_rendered/tests/reconcile.sql"
  run "./agents/tools/ask_genie.sh ${GENIE_SPACE_ID:?} 'Why did the last migration run fail the gate?'"
  run "./agents/tools/inject_fault.sh --revert"
}

scene_genie() {
  say "Control-plane Genie:"
  run "./agents/tools/ask_genie.sh ${GENIE_SPACE_ID:?} 'Did the last migration run ship?'"
}

scene_manifest() {
  say "Gate manifest:"
  run "./agents/tools/render_manifest_table.py agents/out/\$(cat agents/out/CURRENT_RUN)/migration_manifest.json"
}

record_one() {
  local name="$1"
  local fn="scene_${name}"
  command -v asciinema >/dev/null || { echo "asciinema required" >&2; exit 1; }
  asciinema rec -c "bash -c '$(declare -f say run "$fn"); $fn'" \
    --cols "$COLS" --rows "$ROWS" --idle-time-limit "$IDLE_LIMIT" \
    "${CAST_DIR}/${name}.cast"
}

case "${1:-all}" in
  all) for s in bootstrap setup job fault genie manifest; do record_one "$s"; done ;;
  bootstrap|setup|job|fault|genie|manifest) record_one "$1" ;;
  *) echo "usage: $0 [all|bootstrap|setup|job|fault|genie|manifest]" >&2; exit 1 ;;
esac
