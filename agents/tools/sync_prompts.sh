#!/usr/bin/env bash
# Sync agents/prompts/*.md → Cursor (.cursor/agents) + GitHub Copilot (agents/github-copilot).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROMPTS_DIR="${REPO_ROOT}/agents/prompts"
AGENTS_DIR="${REPO_ROOT}/.cursor/agents"
COPILOT_DIR="${REPO_ROOT}/agents/github-copilot"

mkdir -p "$AGENTS_DIR" "$COPILOT_DIR"

sync_cursor() {
  local prompt_file="$1" name="$2" readonly_flag="$3" description="$4"
  local out_file="${AGENTS_DIR}/${name}.md"
  {
    echo "---"
    echo "name: ${name}"
    echo "description: ${description}"
    echo "model: inherit"
    if [ "$readonly_flag" = "true" ]; then echo "readonly: true"; else echo "readonly: false"; fi
    echo "---"
    echo
    cat "${PROMPTS_DIR}/${prompt_file}"
  } > "$out_file"
  echo "[sync_prompts] cursor ${out_file}"
}

sync_copilot() {
  local prompt_file="$1" name="$2"
  local out_file="${COPILOT_DIR}/${name}.md"
  {
    echo "# ${name}"
    echo
    echo "Portable stage instructions (same body as agents/prompts/${prompt_file})."
    echo "Use in GitHub Copilot Chat / coding agent. Coordinator owns the run."
    echo
    cat "${PROMPTS_DIR}/${prompt_file}"
  } > "$out_file"
  echo "[sync_prompts] copilot ${out_file}"
}

sync_cursor "00_coordinator.md" "edw-coordinator" "false" \
  "Owns run_id; discover → assess → convert fan-out (disk artifacts) → persist helpers → job wiring WARN → test → gate. Track B or after demo-guide."
sync_cursor "01_assess.md" "edw-assess" "true" \
  "Inventory → migration backlog JSON (empty OK if routines skipped). No skip field; unique target_paths. Readonly."
sync_cursor "02_convert.md" "edw-convert" "false" \
  'Convert one T-SQL/MySQL routine to silver/gold notebook + convert/<item_id>.json; land-first bronze reads; validate_artifact before exit.'
sync_cursor "03_test.md" "edw-test" "true" \
  "Run reconcile SQL, query ops.reconcile_results, return reconcile_report.json. Readonly."
sync_cursor "04_gate.md" "edw-gate" "true" \
  "Deterministic ship/no-ship from inventory, conversions, reconcile, agent_events; proof SQL; table-only when routines skipped. Readonly."
sync_cursor "05_demo_guide.md" "edw-demo-guide" "false" \
  'Track A guided demo: preflight → bootstrap WWI → setup → coordinator checkpoints; firewall/AutoPause + job wiring WARN.'
sync_cursor "06_start.md" "edw-start" "false" \
  'Front door: start → soft status + phrase menu; CURRENT_RUN resume hint; enterprise SoD from docs. No bootstrap until choice.'

for pair in \
  "00_coordinator.md:edw-coordinator" \
  "01_assess.md:edw-assess" \
  "02_convert.md:edw-convert" \
  "03_test.md:edw-test" \
  "04_gate.md:edw-gate" \
  "05_demo_guide.md:edw-demo-guide" \
  "06_start.md:edw-start"
do
  sync_copilot "${pair%%:*}" "${pair##*:}"
done

cat > "${COPILOT_DIR}/README.md" <<'EOF'
# GitHub Copilot adapter

Stage instruction files are generated from `agents/prompts/` by `agents/tools/sync_prompts.sh`.

**Front door:** open `edw-start.md` and say `start` for status + phrase menu.

**CLI setup (Cursor \`agent\` + Copilot \`copilot\`):** see \`docs/cli-setup.md\`.

**Track A guided demo:** \`edw-demo-guide.md\` (or menu item 1).

**Track B (Azure SQL or MySQL):** \`edw-coordinator.md\` (or menu items 2–3).
EOF

echo "[sync_prompts] done."
