#!/usr/bin/env bash
# Sync agent prompts (agents/prompts/*.md) into Cursor subagent files
# (.cursor/agents/*.md) so prompts stay portable while Cursor gets the
# frontmatter it needs. Single source of truth: agents/prompts/.
#
# Run after editing any prompt:
#   ./agents/tools/sync_prompts.sh
#
# Idempotent. Overwrites .cursor/agents/*.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROMPTS_DIR="${REPO_ROOT}/agents/prompts"
AGENTS_DIR="${REPO_ROOT}/.cursor/agents"

mkdir -p "$AGENTS_DIR"

# Map prompt file -> (subagent name, readonly, description)
# Descriptions are kept short and specific so the coordinator delegates correctly.
sync_one() {
  local prompt_file="$1"
  local name="$2"
  local readonly_flag="$3"
  local description="$4"

  local out_file="${AGENTS_DIR}/${name}.md"
  {
    echo "---"
    echo "name: ${name}"
    echo "description: ${description}"
    echo "model: inherit"
    [ "$readonly_flag" = "true" ] && echo "readonly: true" || echo "readonly: false"
    echo "---"
    echo
    cat "${PROMPTS_DIR}/${prompt_file}"
  } > "$out_file"
  echo "[sync_prompts] wrote ${out_file}"
}

sync_one "00_coordinator.md" "edw-coordinator" "false" \
  "Drives an EDW-to-Databricks migration run end-to-end. Owns the run_id, delegates to edw-assess, edw-convert, edw-test, and edw-gate subagents in order, writes all JSON artifacts on their behalf, and enforces a bounded retry loop on gate failures. Launch this agent to start a migration run."

sync_one "01_assess.md" "edw-assess" "true" \
  "Inventory the source EDW (WideWorldImportersDW via the wwi_dw_fed foreign catalog and legacy/procs/*.sql) and produce a migration backlog of procs to convert. Readonly — returns structured JSON to the coordinator. Launch via the edw-coordinator subagent, not directly."

sync_one "02_convert.md" "edw-convert" "false" \
  "Convert one legacy T-SQL stored procedure (from legacy/procs/) into a Databricks Spark SQL notebook under databricks/silver/ or databricks/gold/, following the medallion contract and convert_style.md. Non-readonly — writes notebooks only. Launch via the edw-coordinator subagent, not directly."

sync_one "03_test.md" "edw-test" "true" \
  "Run reconcile.sql against the medallion tables and the legacy fixtures, then return a reconcile_report.json with pass/fail per check. Readonly — returns structured JSON to the coordinator. Launch via the edw-coordinator subagent, not directly."

sync_one "04_gate.md" "edw-gate" "true" \
  "Make a deterministic ship/no-ship decision for a migration run based on structured inputs (migration_backlog, proc_conversion_map, reconcile_report, ops.agent_events). Readonly — returns the migration_manifest.json to the coordinator. Not a writer, not a doc author. Launch via the edw-coordinator subagent, not directly."

echo "[sync_prompts] done. ${AGENTS_DIR}/*.md regenerated from ${PROMPTS_DIR}/."
