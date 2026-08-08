# Cursor wiring

- `agents/` — generated subagents (`edw-start`, `edw-demo-guide`, `edw-coordinator`, …) from `agents/prompts/` via `agents/tools/sync_prompts.sh`
- `rules/edw-start.mdc` — bare `start` / `menu` / `help` → status + phrase menu
- `hooks.json` + `hooks/` — lifecycle events → `${DATABRICKS_CATALOG}.ops.agent_events`
- Root resolution: `hooks/_repo_root.sh` → `agents/tools/repo_root.sh` (not cwd / not GNU `find`)

**Front door:** open the **repo root**, type `start` (or launch `edw-start`). Choose menu **1** for the guided demo; preflight asks for login/tools if needed.
