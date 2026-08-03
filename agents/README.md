# agents/

Portable prompts + contracts. Cursor and GitHub Copilot adapters are generated.

**Human onboarding:** [docs/getting-started.md](../docs/getting-started.md) · [docs/agent-setup.md](../docs/agent-setup.md)

```bash
./agents/tools/sync_prompts.sh
```

## Stages

| Agent | Role |
|---|---|
| `edw-demo-guide` | Guided demo after az + Databricks login |
| `edw-coordinator` | Track B: Azure SQL or MySQL → discover → convert → gate |
| `edw-assess` | Backlog from inventory (empty OK if routines skipped) |
| `edw-convert` | T-SQL / MySQL routine → silver/gold SQL |
| `edw-test` | Generated reconcile |
| `edw-gate` | Ship/no-ship |

## Tools

| Tool | Purpose |
|---|---|
| `materialize_demo_env.sh` | Build `.env` from logins |
| `render_sql.sh` | Catalog/federation render (`SOURCE_TYPE`) → `_rendered/` |
| `resolve_source_env.sh` | Map `SOURCE_*` / `AZ_SQL_*` |
| `print_observability_urls.sh` | Control Plane + Genie URLs |
| `record_agent_event.sh` | Insert ops.agent_events row |
| `ensure_run_events.py` | Table-only convert/skipped events for Gate |
| `discover_inventory.py` | Base tables + procs/routines (`SOURCE_TYPE`) |
| `generate_from_inventory.py` | Land + reconcile SQL |
| `run_sql.sh` | Statement Execution API |
| `sync_prompts.sh` | Cursor + Copilot |

Copilot copies: [`github-copilot/`](github-copilot/).
