# Cursor wiring

- `agents/` — generated subagents (`edw-demo-guide`, `edw-coordinator`, …) from `agents/prompts/` via `agents/tools/sync_prompts.sh`
- `hooks.json` + `hooks/` — lifecycle events → `${DATABRICKS_CATALOG}.ops.agent_events`
- Root resolution: `hooks/_repo_root.sh` → `agents/tools/repo_root.sh` (not cwd / not GNU `find`)

**Guided demo:** open the **repo root**, launch `edw-demo-guide`, say the kickoff; preflight asks for login/tools if needed.
