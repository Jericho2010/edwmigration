#!/usr/bin/env bash
# record_demo.sh — record the terminal scenes behind the README demo GIFs.
#
# Each scene is a short narrated terminal session recorded with asciinema
# (docs/media/casts/<scene>.cast) and converted to GIF with agg
# (docs/img/demo_<scene>.gif). Recording runs the REAL commands against the
# live workspace — run scenes in the order below so the data tells a coherent
# story (seed → job → fault arc → genie → manifest).
#
# Usage:
#   ./docs/media/record_demo.sh all            # record + convert every scene
#   ./docs/media/record_demo.sh fault          # one scene
#   ./docs/media/record_demo.sh play fault     # replay a scene live (no rec)
#   ./docs/media/record_demo.sh gif            # (re)convert casts to GIFs only
#
# Env: DATABRICKS_HOST / TOKEN / WAREHOUSE_ID, BUNDLE_VAR_warehouse_id
# (sourced from .env if present), GENIE_SPACE_ID (from create_genie_space.sh).
# Requires: asciinema, agg (GIF step), jq, curl, databricks CLI.
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
IDLE_LIMIT=1.5        # asciinema: cap recorded silence at 1.5s
TYPE_DELAY=0.025      # seconds per fake-typed character
SAY_PAUSE=1.5

# ---------------------------------------------------------------------------
# demo-magic helpers
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# scenes
# ---------------------------------------------------------------------------
scene_seed() {
  say "An EDW migration demo that needs no Azure."
  say "Seed the 'legacy warehouse' (source_fed) straight into the lakehouse:"
  run "./databricks/offline/seed_source.sh"
  say "Deterministic WWI-shaped data: cities, customers, stock items, 25k sales."
}

scene_job() {
  say "Same bundle, same DAG — run the medallion pipeline over the seed:"
  run "databricks bundle run edw_migration_medallion -t dev"
  say "Smoke -> bronze -> silver -> gold -> fixtures -> reconcile -> lineage."
}

scene_fault() {
  say "The gate is the hero. Inject legacy-side drift (a stale export):"
  run "./agents/tools/inject_fault.sh --fixture fact_sale_count --delta 1000000"
  say "Re-run the correctness checks:"
  run "./agents/tools/run_sql.sh --file databricks/tests/reconcile.sql"
  say "One failing check -> the gate blocks the run. Ask the copilot why:"
  run "./agents/tools/ask_genie.sh ${GENIE_SPACE_ID:?GENIE_SPACE_ID must be set} 'Why did the last migration run fail the gate?'"
  say "The DBA confirms the export was stale. Close the loop:"
  run "./agents/tools/inject_fault.sh --revert"
  run "./agents/tools/run_sql.sh --file databricks/tests/reconcile.sql"
  say "Green again — and nothing shipped while the gate was red."
}

scene_genie() {
  say "The same lakehouse, in plain English. The migrated gold marts:"
  run "./agents/tools/ask_genie.sh ${GENIE_SPACE_ID:?GENIE_SPACE_ID must be set} 'Top 10 stock items by gross revenue?'"
  run "./agents/tools/ask_genie.sh ${GENIE_SPACE_ID:?GENIE_SPACE_ID must be set} 'How many current customers are there per country?'"
  say "The space is code: databricks/genie/space_config.json."
}

scene_manifest() {
  say "Deterministic ship/no-ship — the gate manifest:"
  run "make offline-gate"
  say "Blockers, retries, verdict: a row in the lakehouse, not a Slack message."
}

SCENES="seed job fault genie manifest"

# ---------------------------------------------------------------------------
# record / convert
# ---------------------------------------------------------------------------
record_scene() {
  local scene="$1"
  echo "[record] scene=${scene} -> ${CAST_DIR}/${scene}.cast"
  asciinema rec --overwrite --quiet \
    --cols "$COLS" --rows "$ROWS" \
    --idle-time-limit "$IDLE_LIMIT" \
    --title "edw-migration demo: ${scene}" \
    -c "bash ${BASH_SOURCE[0]} __play__ ${scene}" \
    "${CAST_DIR}/${scene}.cast"
}

gif_scene() {
  local scene="$1"
  echo "[gif] ${scene}.cast -> docs/img/demo_${scene}.gif"
  agg --font-size 15 --speed 1.0 \
    "${CAST_DIR}/${scene}.cast" \
    "${GIF_DIR}/demo_${scene}.gif"
}

cmd="${1:-all}"
shift || true

case "$cmd" in
  __play__)
    cd "$REPO_ROOT"
    "scene_$1"
    ;;
  play)
    cd "$REPO_ROOT"
    "scene_${1:?play needs a scene name}"
    ;;
  gif)
    for s in ${1:-$SCENES}; do gif_scene "$s"; done
    ;;
  all)
    for s in $SCENES; do
      record_scene "$s"
      gif_scene "$s"
    done
    ;;
  *)
    record_scene "$cmd"
    gif_scene "$cmd"
    ;;
esac
