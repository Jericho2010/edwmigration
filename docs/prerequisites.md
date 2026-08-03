# Prerequisites

Install only what your track needs. Agents / Makefile tell you the one missing tool.

| Tool | When required | Verify |
|---|---|---|
| Databricks CLI | Always | `databricks --version` (0.281+) |
| python3 | Always | `python3 --version` (3.10+) |
| jq, curl | Always | `jq --version` |
| Cursor (or GitHub Copilot) | Agent UX | repo opens with agents |
| Azure CLI | Track A bootstrap; optional MySQL firewall | `az account show` |
| SqlPackage + sqlcmd | **Track A bootstrap / proc export only** — **not** `make setup` | `SqlPackage /version` |
| mysql client | MySQL **routine** export only (tables work without it) | `mysql --version` |

## Databricks privileges

- `CREATE CONNECTION` on the metastore (or admin)
- `CREATE CATALOG` on the metastore
- Secret scopes + Statement Execution on a **serverless** SQL warehouse

## Track A logins

```bash
az login
databricks auth login --host https://<your-workspace>.cloud.databricks.com
```

## Track B MySQL

```bash
databricks auth login --host https://<your-workspace>.cloud.databricks.com
# optional: az login — firewall help only
```

`.env`: `SOURCE_TYPE=mysql` + `SOURCE_HOST` / `SOURCE_PORT` / `SOURCE_DATABASE` / `SOURCE_USER` / `SOURCE_PASSWORD` + Databricks sink. See `infra/azure/.env.example`.

## Track B existing Azure SQL

Same Databricks login. `.env`: `SOURCE_TYPE=sqlserver` (or omit) + `SOURCE_*` **or** `AZ_SQL_*`. **SqlPackage is not required for `make setup`.**
