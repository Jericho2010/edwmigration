# databricks/uc/ — Unity Catalog + Lakehouse Federation setup

## Files

- `01_federation_setup.sql` — catalog/schemas, connection, foreign catalog,
  grants, `source_fed.*` views. Uses `{{AZ_SQL_HOST}}` / `{{AZ_SQL_ADMIN}}`
  placeholders — render with `agents/tools/render_federation_sql.sh`.
- `02_federation_smoke.sql` — fail-fast smoke (Databricks SQL Scripting).
- `03_ops_and_views.sql` — `ops.*` tables (incl. `agent_events` with
  `CLUSTER BY`) + `source_fed` views. Idempotent.

## Run order

```bash
# Prereqs: bootstrap.sh done; secret scope edw-migration exists;
# DATABRICKS_WAREHOUSE_ID set in .env.

./agents/tools/render_federation_sql.sh > /tmp/01_federation_setup.rendered.sql
./agents/tools/run_sql.sh --file /tmp/01_federation_setup.rendered.sql
./agents/tools/run_sql.sh --file databricks/uc/03_ops_and_views.sql
./agents/tools/run_sql.sh --file databricks/uc/02_federation_smoke.sql
```

The medallion job runs `02_federation_smoke.sql` as its first task.

## Catalog model

```text
wwi_dw_fed        (FOREIGN; Azure SQL WideWorldImportersDW)
edw_migration     (MANAGED)
  source_fed / bronze / silver / gold / ops
```

## Free Edition notes

Warm the Azure SQL DB before the first federation query. See
[docs/limits.md](../../docs/limits.md).
