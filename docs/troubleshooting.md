# Troubleshooting

| Symptom | Fix |
|---|---|
| `az account show` fails | `az login` (Track A / firewall help only) |
| Databricks auth fails | `databricks auth login --host …` or set `DATABRICKS_TOKEN` |
| `make setup` wants SqlPackage | Only `make bootstrap` / `make demo` need SqlPackage. Existing SQL/MySQL setup needs connection fields only. |
| Federation JDBC / cold Azure SQL | Warm DB (`SELECT 1`); check firewall ([firewall.md](firewall.md)) |
| MySQL federation SSL / cert errors | SSL is required. Default `SOURCE_TRUST_SERVER_CERTIFICATE=true`. Set `false` only if you have a working CA trust path. |
| MySQL unreachable from Free Edition | Open Flexible Server firewall / public access for demo; prefer lock-down for real data ([firewall.md](firewall.md)) |
| MySQL uses wrong catalog names (`wwi_dw_fed`) | Remove `FOREIGN_CATALOG` / `CONNECTION_NAME` from `.env` or set `mysql_fed` / `azure_mysql_edw` |
| `CREATE CONNECTION` denied | Need metastore `CREATE CONNECTION` (+ `CREATE CATALOG`) |
| Smoke: 0 foreign tables | Wrong database name / connection / bacpac not imported |
| `mysql` CLI missing | Tables still migrate; routines skipped with `routines_skipped_reason`. Install `mysql` client to export routines. |
| Job missing `10_land_all.sql` | Run discover + generate for a `run_id`, then `make render` |
| Gate fails unconverted | Convert backlog items **or** confirm table-only + `ensure_run_events.py` ran |
| Gate fails missing agent_events | `python3 agents/tools/ensure_run_events.py --run-id …` then record test/gate events |
| Dashboard empty | Hooks need Cursor run + `DATABRICKS_CATALOG` in `.env` for flush |
| No Dashboard URL | `make print-urls` after `make deploy` |
| Genie create fails | Ops tables must exist (`make setup`); warehouse ID set |

Offline seed mode was removed — use the guided demo or a real Azure SQL / MySQL source.
