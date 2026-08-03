# Runbook

See also [agent-setup.md](agent-setup.md) for Cursor/Copilot agents and kickoff sentences.

## Track A — Guided demo (Azure SQL + WWI)

1. `az login` and `databricks auth login --host <workspace>` (or PAT).
2. In Cursor, launch **`edw-demo-guide`**: *Set up the EDW demo and walk me through the migration.*
3. Watch **[dev] EDW Migration Control Plane** and the Genie URL the guide prints.
4. When finished: ask the guide to teardown, or `make teardown`.

Scripted: `make materialize-demo && make demo`

## Track B — Azure MySQL

You provide four connection fields + catalog (+ Databricks auth). Agents do the rest.

```bash
cp infra/azure/.env.example .env
# SOURCE_TYPE=mysql
# SOURCE_HOST / SOURCE_PORT(3306) / SOURCE_DATABASE / SOURCE_USER / SOURCE_PASSWORD
# DATABRICKS_HOST / token-or-profile / DATABRICKS_WAREHOUSE_ID / DATABRICKS_CATALOG
# Optional: FOREIGN_CATALOG=mysql_fed CONNECTION_NAME=azure_mysql_edw
make setup
# Launch edw-coordinator:
#   Migrate my Azure MySQL into catalog <DATABRICKS_CATALOG>.
```

Free Edition: open the MySQL firewall (or public access) so the warehouse can reach the host — prefer lock-down for real data. Optional: `az mysql flexible-server firewall-rule ...` if you are logged into Azure and ask the agent.

Tables always migrate. Routines export when the `mysql` CLI is installed; otherwise Assess notes the skip and Gate still ships on land + reconcile.

## Track B — Existing Azure SQL

```bash
cp infra/azure/.env.example .env
# SOURCE_TYPE=sqlserver (default) + SOURCE_* or AZ_SQL_* + DATABRICKS_*
make setup
# Launch edw-coordinator — Start an EDW migration run against my Azure SQL.
```

Privileges: Databricks `CREATE CONNECTION` + `CREATE CATALOG` (or admin). Source login that can read tables (and export procs/routines when you want Convert).

## Makefile

| Target | Purpose |
|---|---|
| `make materialize-demo` | Build `.env` from logins (Track A) |
| `make bootstrap` | Free Azure SQL + WWI bacpac |
| `make setup` | Secrets + federation + ops + deploy + genie (sqlserver or mysql) |
| `make deploy` / `make run` | Bundle deploy / job |
| `make teardown` | Delete Azure RG (demo) |
| `make sync-prompts` | Regenerate Cursor + Copilot agents |

## After discovery

Coordinator runs `discover_inventory.py` + `generate_from_inventory.py`, then Convert (if any), then `make deploy && make run`, Test, Gate. If `tables_total > 200`, confirm before land.

## Trust checklist

1. Inventory written (`agents/out/<run_id>/inventory.json`)
2. Bronze reconcile pass
3. Gate `blockers` empty — print Dashboard + Genie URLs
