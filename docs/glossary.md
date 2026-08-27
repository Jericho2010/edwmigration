# Glossary

Short definitions for terms used in this repo. ← [Getting started](getting-started.md)

| Term | Plain meaning |
|---|---|
| **Unity Catalog (UC)** | Databricks governance layer: catalogs, schemas, tables, permissions. |
| **Catalog** | Top-level container you name (`DATABRICKS_CATALOG`) holding `bronze` / `silver` / `gold` / `ops`. |
| **Lakehouse Federation** | Live *read* of an external database (Azure SQL or MySQL) into Databricks without copying first. |
| **Foreign catalog** | UC catalog that mirrors the source DB via a Federation **connection**. |
| **Connection** | UC object with host/user/password (secret) for SQL Server or MySQL. |
| **Bronze / silver / gold** | Medallion layers: raw land → conformed → marts. |
| **`source_fed`** | Views in your catalog that point at federated source tables. |
| **`ops`** | Control tables: inventory, backlog, reconcile, Gate, agent events. |
| **Discover** | Auto-list base tables (+ procs/routines when tools allow). |
| **Land** | `CREATE OR REPLACE` bronze tables from the federated source. |
| **Convert** | Turn one stored procedure / routine into Spark SQL (`.sql` under `databricks/silver\|gold`), plus a result JSON for merge. Those files are run artifacts (gitignored). Workspace **notebooks** are a gallery copy of that SQL after Land. |
| **Job skeleton** | Committed medallion DAB: `federation_smoke` → `bronze_land` → `stage_fixtures` → `reconcile` → `lineage_check`. No WWI silver/gold tasks. |
| **Job wiring** | `check_job_wiring.py --apply` inserts Convert SQL as job tasks from Assess `reads`/`writes` (peak ≤ 5). `make reset-sink` restores the skeleton. |
| **FOREIGN_CATALOG** | Engine default `sqlserver_fed` / `mysql_fed`. Track A `.env` may override; it is not a WWI-named catalog by default. |
| **demo/wwi/reference** | Teaching copies of WWI silver/gold SQL. Not executed and not copied into the job. |
| **Notebooks folder** | Workspace gallery `/Users/<you>/edwmigration_YYYYMMDD` — SQL notebooks imported by `publish_run_notebooks.py` after Land. Job tasks stay `sql_task`. Path is in `agents/out/<run_id>/notebooks.json`. |
| **Catalog URL** | Unity Catalog explorer for `DATABRICKS_CATALOG` (`make print-urls` after setup). |
| **Job URL** | Medallion job in Databricks Jobs — skeleton plus wired Convert tasks (`make print-urls` after `make deploy`). |
| **Fan-out** | Coordinator launches up to **5** `edw-convert` agents in parallel per wave (unique `target_path`s). |
| **run_id** | UUID for one migration run; artifacts live under `agents/out/<run_id>/`. |
| **convert_summary** | Merged Convert counts (`converted` / `blocked`) after a wave — `agents/out/<run_id>/convert_summary.json`. |
| **Reconcile / Test** | Compare bronze row counts to source; write pass/fail. |
| **Gate** | Deterministic ship / no-ship from inventory + reconcile + conversions (empty blockers). Demo ≥10/≥5 counts are a separate guide check, not Gate. |
| **Control Plane** | AI/BI dashboard over `ops.*` for the migration run. |
| **Genie** | Natural-language room over ops (and later silver/gold) tables. |
| **MLflow / observe** | Live agent/tool span tree in Databricks Experiments (`/Shared/edw-migration`). Soft dual-write from Cursor hooks + milestones; does not replace Control Plane/Genie. See [mlflow.md](mlflow.md). |
| **`observe_url`** | Link to the live MLflow trace for the current `run_id` (printed after `mlflow_observe init` / `make print-urls`). |
| **`mlflow_context.json`** | Per-run file under `agents/out/<run_id>/` holding experiment/trace ids, open spans, and `observe_url`. |
| **Track A** | Guided demo: WideWorldImporters **source** on free Azure SQL. Convert still writes the Databricks warehouse. |
| **Track B** | Your existing Azure SQL or Azure MySQL. |
| **start / edw-start** | Front door: soft status + numbered phrase menu; routes to demo-guide, coordinator, URLs, teardown, or enterprise docs. |
| **Kickoff sentence** | A phrase from the menu (or pasted directly) to start `edw-demo-guide` or `edw-coordinator`. |
| **SoD** | Segregation of duties — split create / convert / approve / deploy. See [enterprise.md](enterprise.md). |
| **Service principal (SP)** | Non-human identity for jobs and CI (enterprise), instead of a person’s PAT. |
| **PAT** | Personal access token — fine for demos; not the enterprise prod pattern. |
| **SqlPackage** | Tool that imports `.bacpac` files — used in Track A bootstrap, not everyday Track B setup. |

## Next

→ [What you get](what-you-get.md) · [Enterprise](enterprise.md) · [Architecture](architecture.md) · [MLflow](mlflow.md)
