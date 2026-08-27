# Troubleshooting

Something broke? Find the symptom, apply the one-line fix, re-run the agent step.

← [Getting started](getting-started.md) · [Guided demo](guided-demo.md) · [Your database](your-database.md)

| Symptom | Fix |
|---|---|
| Agents missing in Cursor | Open **repo root**; run `make sync-prompts`; reload window |
| `az account show` fails | `az login` (Track A / firewall help) |
| `AADSTS700082` / expired refresh token | `az logout` then `az login` (portal login does not refresh CLI) |
| Sub visible but `az group list` → AuthorizationFailed | No RBAC on the sub — **Global Admin in Entra ≠ Owner on the subscription** — see [azure-access-unblocking.md](azure-access-unblocking.md) |
| Databricks auth fails / CLI ignores `~/.databrickscfg` | `.env` has `DATABRICKS_HOST` without `DATABRICKS_TOKEN`. Repo tools overlay a matching CLI profile. Re-login: `databricks auth login --host …` or set `DATABRICKS_TOKEN` |
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
| Dashboard empty / stale | Hooks buffer not flushed, or prior-run ops rows. Flush threshold is now 1 (async from the 15s hook; milestones force-flush). Latest-run widgets prefer `ops.agent_events` then the manifest. If widgets show prior-run reconcile/backlog: `make reset-sink` (Databricks only; keeps Azure). Gate Hero empty until Gate writes `migration_manifest_current`; tables-landed (`load_control`) should move at Land. |
| Events stuck in `events.buf.jsonl` | Force flush: `.cursor/hooks/_flush_events.sh $(cat agents/out/CURRENT_RUN)` or lower `AGENT_EVENT_FLUSH_THRESHOLD` (default 1). |
| No Dashboard / Genie URL | `make print-urls` after `make deploy` / `make genie` |
| Workspace empty / no notebooks | After Land: `python3 agents/tools/publish_run_notebooks.py --run-id <id>` then `make print-urls`. Gallery is `/Users/<you>/edwmigration_YYYYMMDD` (SQL notebooks). Job stays `sql_task`. |
| No Catalog / Job URL | Catalog: after `make setup`. Job: after `make deploy`. Both print from `make print-urls`. |
| No MLflow `observe_url` | `make observe-setup`, then init via `.venv`: `"$(./agents/tools/resolve_python.sh)" agents/tools/mlflow_observe.py init --run-id <id>`. Setup-time `print-urls` often has no run yet. See [mlflow.md](mlflow.md). |
| `mlflow_context.json` has `enabled: false` | Fix `.venv`/mlflow (`make observe-setup`); check `error` field; Shared experiment create may need fallback / workspace perms. See [mlflow.md](mlflow.md). |
| MLflow `Parent span ... not found` / duplicate RUNNING runs | Cross-process hooks cannot share a trace. `init` starts a single `serve` daemon; hooks only append to `spans.buf.jsonl`. Do **not** `--force` re-init per hook. Purge orphans: `"$(./agents/tools/resolve_python.sh)" agents/tools/mlflow_observe.py experiment-purge` or `make teardown-databricks`. |
| Silent agent / empty Dashboard **during** Convert | Assess/Convert/Test/Gate must be Cursor **`edw-*`** subagents so hooks fire. Opaque Task / `generalPurpose` without `dual_write_agent_lifecycle.sh` (Convert: `--item-id` per item) produces silence. Paste `./agents/tools/observe_status.sh --stage <Name>` after each stage. |
| Agent self-starts migration on bare `start` | Bug — only menu **1/2/3** may migrate. See `agents/prompts/06_start.md` / `.cursor/rules/edw-start.mdc`. |
| Genie create/update fails | Ops tables must exist (`make setup`); warehouse ID set. Setup-time `make genie` WARNs on PATCH 400 so Track A continues. After Land, `make genie GENIE_STRICT=1` fails loud. |
| Need clean demo without Azure teardown | `make reset-sink` (tables/rows) or `make teardown-databricks` (catalog, jobs, Genie, MLflow, secrets). Both keep Azure SQL. |

Offline seed mode was removed — use the [guided demo](guided-demo.md) or [your database](your-database.md).

Production-shaped controls (SoD, OAuth, private network): [enterprise.md](enterprise.md).
