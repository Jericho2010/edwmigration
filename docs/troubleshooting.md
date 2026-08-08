# Troubleshooting

Something broke? Find the symptom, apply the one-line fix, re-run the agent step.

← [Getting started](getting-started.md) · [Guided demo](guided-demo.md) · [Your database](your-database.md)

| Symptom | Fix |
|---|---|
| Agents missing in Cursor | Open **repo root**; run `make sync-prompts`; reload window |
| `az account show` fails | `az login` (Track A / firewall help) |
| `AADSTS700082` / expired refresh token | `az logout` then `az login` (portal login does not refresh CLI) |
| Sub visible but `az group list` → AuthorizationFailed | No RBAC on the sub — **Global Admin in Entra ≠ Owner on the subscription** — see [azure-access-unblocking.md](azure-access-unblocking.md) |
| Databricks auth fails | `databricks auth login --host …` or set `DATABRICKS_TOKEN` |
| `make setup` wants SqlPackage | Only `make bootstrap` / `make demo` need it. Track B setup needs connection fields only. |
| Federation JDBC / cold Azure SQL | Warm DB (`SELECT 1`); check [firewall](firewall.md) |
| MySQL SSL / cert errors | SSL required. Default `SOURCE_TRUST_SERVER_CERTIFICATE=true` |
| MySQL unreachable from Free Edition | Open Flexible Server firewall / public access for demo — [firewall](firewall.md) |
| MySQL uses `wwi_dw_fed` names | Remove stale `FOREIGN_CATALOG` / `CONNECTION_NAME` or set mysql defaults |
| `CREATE CONNECTION` denied | Need metastore `CREATE CONNECTION` (+ `CREATE CATALOG`) |
| Smoke: 0 foreign tables | Wrong database name / connection / bacpac not imported |
| `mysql` CLI missing | Tables still migrate; routines skipped with a note |
| Job missing `10_land_all.sql` / placeholder land | Discover + generate for a `run_id`, then `make render` — `make run` now refuses placeholder land |
| Hooks events on wrong run / `unknown` | Open **repo root**; ensure `agents/out/CURRENT_RUN` exists after coordinator start |
| Gate fails unconverted | Convert backlog **or** table-only run with `ensure_run_events.py` |
| Gate fails missing agent_events | `ensure_run_events.py` (coordinator + convert/skipped) then `record_agent_event` for assess/test/gate after each persist helper |
| Dashboard empty | Hooks need a Cursor agent run + `DATABRICKS_CATALOG` in `.env` |
| No Dashboard / Genie URL | `make print-urls` after `make deploy` / `make genie` |
| Genie create fails | Ops tables must exist (`make setup`); warehouse ID set |

Offline seed mode was removed — use the [guided demo](guided-demo.md) or [your database](your-database.md).

Production-shaped controls (SoD, OAuth, private network): [enterprise.md](enterprise.md).
