# Architecture

## Engine vs demo pack

- **Engine:** `SOURCE_TYPE` (`sqlserver`|`mysql`) → Lakehouse Federation → discover base tables (+ procs/routines) → generate bronze land/reconcile → agent Convert → job → Gate → Dashboard/Genie.
- **Demo pack (`demo/wwi`, `infra/azure`, `legacy/*`):** optional WWI sample for Track A. Gate never requires WWI object names.

## Catalog model

User supplies `DATABRICKS_CATALOG`. Schemas: `source_fed`, `bronze`, `silver`, `gold`, `ops`.

Foreign catalog mirrors the source database via `CONNECTION` `TYPE SQLSERVER` or `TYPE MYSQL`. Password lives in secret scope key `source-password` (sqlserver also keeps `azure-sql-password` alias).

## Discovery

- Tables: `information_schema` on the foreign catalog, `BASE TABLE` only.
- SQL Server procs: sqlcmd / `export_proc_source.sh`.
- MySQL routines: `mysql` CLI when present; otherwise `routines_skipped_reason` and table-only Gate.
- Landing names: `Dimension.X`→`dim_*`, `Fact.X`→`fact_*`, else `schema_table`.

## Observability

Hooks → `ops.agent_events`. Control Plane dashboard (`dataset_catalog` / `ops`). Genie with dynamic `table_identifiers`.

## Auth

PAT supported now. OAuth (`databricks auth login`) is the enterprise target state.

## Free Edition

Serverless warehouse only; Federation not Lakeflow Connect; job concurrency ≤5. Source must be reachable from Free Edition egress (firewall / public access for demos).
