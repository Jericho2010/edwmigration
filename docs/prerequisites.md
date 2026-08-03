# Prerequisites

| Tool | Min | Verify |
|---|---|---|
| Azure CLI | 2.63+ | `az account show` |
| SqlPackage | 162+ | `SqlPackage /version` |
| sqlcmd | 1.2+ | `sqlcmd -?` |
| Databricks CLI | 0.281+ (0.292+ preferred) | `databricks --version` |
| python3 | 3.10+ | `python3 --version` |
| jq, curl | — | `jq --version` |
| Cursor (or GitHub Copilot) | current | repo opens with agents |

## Databricks privileges

- `CREATE CONNECTION` on the metastore (or admin)
- `CREATE CATALOG` on the metastore
- Ability to create secret scopes / use Statement Execution API on a **serverless** SQL warehouse

## Guided demo logins

```bash
az login
databricks auth login --host https://<your-workspace>.cloud.databricks.com
```

Then launch `edw-demo-guide` — you should not need to hand-craft Azure SQL fields for the sample DW path.
