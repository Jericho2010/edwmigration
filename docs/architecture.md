# Architecture

## Engine vs demo pack

- **Engine:** Azure SQL connection → Lakehouse Federation → discover base tables + procs → generate bronze land/reconcile → agent Convert → job → Gate → Dashboard/Genie.
- **Demo pack (`demo/wwi`, `infra/azure`, `legacy/*`):** optional WWI sample for the guided demo. Gate never requires WWI object names.

## Catalog model

User supplies `DATABRICKS_CATALOG`. Schemas: `source_fed`, `bronze`, `silver`, `gold`, `ops`.

Foreign catalog (default `wwi_dw_fed`) mirrors the Azure SQL database via `CONNECTION` `TYPE SQLSERVER` with password in a secret scope.

## Discovery

- Tables: `information_schema` on the foreign catalog, `BASE TABLE` only.
- Procs: sqlcmd export of user procedures.
- Landing names: `Dimension.X`→`dim_*`, `Fact.X`→`fact_*`, else `schema_table`.

## Observability

Hooks → `ops.agent_events`. Control Plane dashboard (`dataset_catalog` / `ops`). Genie with dynamic `table_identifiers`.

## Auth

PAT supported now. OAuth (`databricks auth login`) is the enterprise target state. SQL Server Entra federation auth is future.

## Free Edition

Serverless warehouse only; Federation not Lakeflow Connect; job concurrency ≤5.
