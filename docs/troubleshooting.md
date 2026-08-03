# Troubleshooting

| Symptom | Fix |
|---|---|
| `az account show` fails | `az login` |
| Databricks auth fails | `databricks auth login --host …` or set `DATABRICKS_TOKEN` |
| Federation JDBC / cold DB | Warm Azure SQL (`SELECT 1` via sqlcmd); check firewall / Free Edition egress ([firewall.md](firewall.md)) |
| `CREATE CONNECTION` denied | Need metastore `CREATE CONNECTION` (+ `CREATE CATALOG`) |
| Smoke: 0 foreign tables | Bacpac not imported / wrong database name / connection options |
| Job missing `10_land_all.sql` | Run discover + generate for a `run_id`, then `make render` |
| Gate fails unconverted | Convert all backlog items; paths under `databricks/silver|gold` only |
| Dashboard empty | Hooks need Cursor run + `DATABRICKS_CATALOG` in `.env` for flush |
| Genie create fails | Ops tables must exist (`make setup`); warehouse ID set |

Offline seed mode was removed — use the guided demo or a real Azure SQL source.
