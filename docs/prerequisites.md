# Prerequisites

Install only what your track needs. Agents tell you the one missing tool if something fails.

| Tool | Track | Verify |
|---|---|---|
| Databricks CLI | A + B | `databricks --version` (0.281+) |
| python3 | A + B | `python3 --version` (3.10+) |
| jq, curl | A + B | `jq --version` |
| Cursor (or GitHub Copilot) | A + B | repo opens with agents |
| Azure CLI | A (demo); B optional for firewall | `az account show` |
| SqlPackage + sqlcmd | A bootstrap / SQL Server proc export | `SqlPackage /version` |
| mysql client | B MySQL **routines** (optional) | `mysql --version` |

Table land for MySQL does **not** require the `mysql` CLI — only routine export does.

## Databricks privileges

- `CREATE CONNECTION` on the metastore (or admin)
- `CREATE CATALOG` on the metastore
- Ability to create secret scopes / use Statement Execution API on a **serverless** SQL warehouse

## Guided demo logins (Track A)

```bash
az login
databricks auth login --host https://<your-workspace>.cloud.databricks.com
```

Then launch `edw-demo-guide` — you should not need to hand-craft Azure SQL fields for the sample DW path.

## Track B MySQL logins

```bash
databricks auth login --host https://<your-workspace>.cloud.databricks.com
# optional: az login  — only if you want the agent to open a firewall rule
```

Put `SOURCE_TYPE=mysql` and `SOURCE_*` in `.env` (see `infra/azure/.env.example`).
