# Runbook

## Guided demo (recommended)

1. Install tools from [prerequisites.md](prerequisites.md).
2. `az login` and `databricks auth login --host <workspace>` (or PAT).
3. In Cursor, launch **`edw-demo-guide`**: *Set up the EDW demo and walk me through the migration.*
4. Watch **[dev] EDW Migration Control Plane** and the Genie URL the guide prints.
5. When finished: ask the guide to teardown, or `make teardown`.

Scripted: `make materialize-demo && make demo`

## Self-serve (existing Azure SQL)

```bash
cp infra/azure/.env.example .env
# Set AZ_SQL_* + DATABRICKS_* including DATABRICKS_CATALOG
set -a; . ./.env; set +a
make setup
# Launch edw-coordinator — discovers all base tables + user procs
```

Privileges: Databricks `CREATE CONNECTION` + `CREATE CATALOG` (or admin). Azure SQL login that can read tables and export proc definitions.

## Makefile

| Target | Purpose |
|---|---|
| `make materialize-demo` | Build `.env` from logins |
| `make bootstrap` | Free Azure SQL + WWI bacpac |
| `make setup` | Federation + ops + deploy + genie |
| `make deploy` / `make run` | Bundle deploy / job |
| `make teardown` | Delete Azure RG |
| `make sync-prompts` | Regenerate Cursor + Copilot agents |

## After discovery

Coordinator runs `discover_inventory.py` + `generate_from_inventory.py`, then Convert, then `make deploy && make run`, Test, Gate. If `tables_total > 200`, confirm before land.
