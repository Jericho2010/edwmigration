# agents/

Portable prompts + contracts. Cursor and GitHub Copilot adapters are generated.

```bash
./agents/tools/sync_prompts.sh
```

## Stages

| Agent | Role |
|---|---|
| `edw-demo-guide` | Guided demo after az + Databricks login |
| `edw-coordinator` | Discover → generate → assess → convert → deploy/run → test → gate |
| `edw-assess` | Backlog from inventory |
| `edw-convert` | Proc → silver/gold SQL |
| `edw-test` | Generated reconcile |
| `edw-gate` | Ship/no-ship |

## Tools

| Tool | Purpose |
|---|---|
| `materialize_demo_env.sh` | Build `.env` from logins |
| `render_sql.sh` | Catalog/federation render → `_rendered/` |
| `discover_inventory.py` | Base tables + procs |
| `generate_from_inventory.py` | Land + reconcile SQL |
| `run_sql.sh` | Statement Execution API |
| `sync_prompts.sh` | Cursor + Copilot |

Copilot copies: [`github-copilot/`](github-copilot/).
