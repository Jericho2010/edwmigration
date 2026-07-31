# databricks/uc/ — Unity Catalog + Lakehouse Federation setup

SQL files that bootstrap the Databricks side of the migration demo.

## Files

- `01_federation_setup.sql` — creates the `edw_migration` catalog + schemas,
  the federation connection to Azure SQL, the `wwi_dw_fed` foreign catalog,
  and the `source_fed.*` convenience views.
- `02_federation_smoke.sql` — fail-fast smoke test. Run as the first task of
  the medallion job. Aborts on JDBC failure with remediation hints.
- `03_ops_and_views.sql` — creates the `ops.*` operational tables
  (`load_control`, `migration_backlog`, `proc_conversion_map`,
  `reconcile_results`, `agent_events`) and re-creates the `source_fed.*`
  views. Idempotent.

## Run order

```bash
# Prereqs: bootstrap.sh has run; secrets scope 'edw-migration' exists.
databricks sql execute --file databricks/uc/01_federation_setup.sql
databricks sql execute --file databricks/uc/03_ops_and_views.sql
databricks sql execute --file databricks/uc/02_federation_smoke.sql
```

The medallion job (`databricks/jobs/edw_migration_medallion.yml`) runs
`02_federation_smoke.sql` as its first task, so manual smoke is optional.

## Catalog model

```text
wwi_dw_fed        (FOREIGN; read-only mirror of Azure SQL WideWorldImportersDW)
  dimension / fact / integration / application

edw_migration     (MANAGED)
  source_fed      -- convenience views over wwi_dw_fed.* (stable snake_case names)
  bronze          -- 1:1 land from source_fed, with audit columns
  silver          -- conformed types, SCD2 on customer, orphan-fact quarantine
  gold            -- 1:1 mapping to legacy Integration.* proc outcomes (marts)
  ops             -- load_control, migration_backlog, proc_conversion_map,
                  -- reconcile_results, agent_events
```

## Free Edition notes

- Serverless SQL warehouse only (no classic clusters).
- Outbound internet is restricted; the federation connection works because
  Azure SQL is on the trusted allowlist, but cold-start failures look like
  network errors. Always warm the DB (`SELECT 1` via sqlcmd) before the first
  federation query.
- See [docs/limits.md](../../docs/limits.md) for full constraints.
