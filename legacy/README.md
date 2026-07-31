# legacy/ — source EDW artifacts

Everything on the **source** side of the migration: WideWorldImportersDW
bacpac, exported stored-procedure T-SQL, and reconcile fixtures.

```text
legacy/
  wideworldimportersdw/   Vendored .bacpac + download_bacpac.sh (SHA pinned)
  procs/                  One .sql file per Integration/Configuration/Application proc
  fixtures/               CSV snapshots + expectations.json for Test/reconcile
```

## `wideworldimportersdw/`

Microsoft sample EDW as a `.bacpac` (~22 MB), **committed** with SHA-256 pin
`96e9b87d…`. `download_bacpac.sh` re-fetches only if missing or hash mismatch.
Bootstrap imports it with `SqlPackage`. Details:
[wideworldimportersdw/README.md](wideworldimportersdw/README.md).

## `procs/`

`export_proc_source.sh` dumps T-SQL for procedures in `[Integration]`,
`[Configuration]`, and `[Application]`. These files are the **Convert**
teaching surface.

Seven `Integration.*` sources are **vendored** here (from Microsoft's
MIT-licensed `sql-server-samples` wwi-dw-ssdt project) so Assess/Convert can
run without a live Azure SQL export — the five `MigrateStaged*Data` procs in
the demo scope (Sale, StockHolding, Customer, City, StockItem) plus the
`GetLineageKey` / `GetLastETLCutoffTime` helpers. A live export overwrites
them with the true on-database definitions.

## `fixtures/`

`export_fixtures.sh` captures reconcile fixtures (mutates DB via Migrate* procs):

| Proc style | Fixture |
|---|---|
| `Get*` (`@LastCutoff` / `@NewCutoff`) | Proc result set as CSV |
| `Migrate*` | Target `Dimension.*` table state after execution |

`build_expectations.sh` regenerates `expectations.json` and
`databricks/tests/13_stage_fixture_expectations.sql` for the job’s
`stage_fixtures` → `reconcile` path.

## Manual usage

Normally invoked by `infra/azure/bootstrap.sh`. Standalone:

```bash
set -a; . ./.env; set +a
./legacy/wideworldimportersdw/download_bacpac.sh
./legacy/procs/export_proc_source.sh
./legacy/fixtures/export_fixtures.sh    # mutates DB
./legacy/fixtures/build_expectations.sh
```
