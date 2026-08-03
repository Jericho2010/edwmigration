# EDW → Databricks Migration

Migrate **Azure SQL** or **Azure MySQL** into a user-named Unity Catalog catalog. Agents discover base tables (and routines/procs), land bronze, convert logic, Gate the run, and show everything in a Control Plane dashboard + Genie.

## You do / Agent does

| You | Agent |
|---|---|
| Open this repo in Cursor ([agent setup](docs/agent-setup.md)) | Loads `edw-demo-guide` / `edw-coordinator` |
| Log in | Writes `.env`, wires Federation |
| One kickoff sentence | Discover → land → convert → job → Gate |
| Watch Dashboard + Genie | Prints URLs; clear blockers if Gate fails |

## Track A — Guided demo (easiest)

1. `az login`
2. `databricks auth login --host <Free Edition URL>` (or PAT)
3. Launch **`edw-demo-guide`**:

   > Set up the EDW demo and walk me through the migration.

Scripted twin: `make materialize-demo && make demo`

## Track B — Your database

**MySQL** — put this in `.env` (see [`.env.example`](infra/azure/.env.example)), then launch **`edw-coordinator`**:

```bash
SOURCE_TYPE=mysql
SOURCE_HOST=myserver.mysql.database.azure.com
SOURCE_PORT=3306
SOURCE_DATABASE=mydb
SOURCE_USER=myuser@myserver
SOURCE_PASSWORD=...
DATABRICKS_HOST=https://dbc-XXXX.cloud.databricks.com
DATABRICKS_WAREHOUSE_ID=...
DATABRICKS_CATALOG=my_edw
```

> Migrate my Azure MySQL into catalog `my_edw`.

**Azure SQL (existing)** — `SOURCE_TYPE=sqlserver` (or omit; demo defaults) + `SOURCE_*` / `AZ_SQL_*`, then `make setup` and launch **`edw-coordinator`**.

No object list. If inventory exceeds 200 tables, confirm before land.

## What you see

- `${DATABRICKS_CATALOG}.bronze.*` for every discovered base table  
- Silver/gold from Convert when procs/routines are in scope  
- **[dev] EDW Migration Control Plane** + Genie (“Did the last run ship?”)  
- Gate ship/no-ship (demo pack also checks ≥10 tables / ≥5 procs as **counts**)

## Docs

| Doc | Purpose |
|---|---|
| [docs/agent-setup.md](docs/agent-setup.md) | Cursor agents + kickoff sentences |
| [docs/runbook.md](docs/runbook.md) | Track A / Track B operator steps |
| [docs/architecture.md](docs/architecture.md) | Engine vs demo pack |
| [docs/prerequisites.md](docs/prerequisites.md) | Tools |
| [docs/lakebridge.md](docs/lakebridge.md) | Comparison (we compete, not compose) |

## License

MIT — see [LICENSE](LICENSE). WideWorldImporters sample is MIT (Microsoft).
