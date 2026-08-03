# Cursor wiring

- `agents/` — generated subagents (`edw-demo-guide`, `edw-coordinator`, …) from `agents/prompts/` via `agents/tools/sync_prompts.sh`
- `hooks.json` + `hooks/` — lifecycle events → `${DATABRICKS_CATALOG}.ops.agent_events`

**Guided demo:** launch `edw-demo-guide` after Azure + Databricks login.
