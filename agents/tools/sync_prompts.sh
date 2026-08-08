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
  "Drives an Azure SQL or Azure MySQL → Databricks migration run end-to-end. Owns the run_id, delegates to edw-assess, edw-convert, edw-test, and edw-gate, and enforces a bounded retry loop on gate failures. Launch for Track B (or after demo-guide)."
sync_cursor "01_assess.md" "edw-assess" "true" \
  "Inventory discovered base tables and procs/routines; produce a migration backlog (empty OK if routines skipped). Readonly."
sync_cursor "02_convert.md" "edw-convert" "false" \
  'Convert one legacy T-SQL proc or MySQL routine into a Databricks Spark SQL notebook under databricks/silver/ or databricks/gold/. Writes agents/out/<run_id>/convert/<item_id>.json for parallel fan-out merge.'
sync_cursor "03_test.md" "edw-test" "true" \
  "Run generated reconcile SQL and return reconcile_report.json. Readonly."
sync_cursor "04_gate.md" "edw-gate" "true" \
  "Deterministic ship/no-ship Gate from inventory, conversions, reconcile, and agent_events. Table-only ship when routines skipped. Readonly."
sync_cursor "05_demo_guide.md" "edw-demo-guide" "false" \
  'Track A guided demo: run preflight_track_a.sh after kickoff, then provision WWI sample source, wire UC, deploy Dashboard/Genie, and step through migration with the user.'

for pair in \
  "00_coordinator.md:edw-coordinator" \
  "01_assess.md:edw-assess" \
  "02_convert.md:edw-convert" \
  "03_test.md:edw-test" \
  "04_gate.md:edw-gate" \
  "05_demo_guide.md:edw-demo-guide"
do
  sync_copilot "${pair%%:*}" "${pair##*:}"
done

cat > "${COPILOT_DIR}/README.md" <<'EOF'
# GitHub Copilot adapter

Stage instruction files are generated from `agents/prompts/` by `agents/tools/sync_prompts.sh`.

**Track A guided demo:** open `edw-demo-guide.md` after `az login` and Databricks auth.

**Track B (Azure SQL or MySQL):** start with `edw-coordinator.md` (or ask Copilot to follow that file).
EOF

echo "[sync_prompts] done."
