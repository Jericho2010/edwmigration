# legacy/ — source EDW artifacts for the migration demo

This directory holds everything that represents the **source** side of the
migration: the WideWorldImportersDW sample database, its stored-procedure
source, and the reconcile fixtures captured from running those procs.

```text
legacy/
  wideworldimportersdw/   WideWorldImportersDW-Standard.bacpac + import_azure_sql.sh
  procs/                  One .sql file per [Integration]/* proc (the migration teaching surface)
  fixtures/               CSV snapshots used by the Test agent to reconcile gold tables
```

## Layout

### `wideworldimportersdw/`

The Microsoft sample EDW in `.bacpac` form. `import_azure_sql.sh` downloads it
from Microsoft's official SQL Server samples release. The bacpac is committed
to the repo so the demo is fully self-contained (no download at demo time).

### `procs/`

`export_proc_source.sh` connects to the Azure SQL database and dumps the
T-SQL source of every stored procedure in the `[Integration]`, `[Configuration]`,
and `[Application]` schemas to one `.sql` file per proc. These files are the
**migration teaching surface** — the Convert agent reads each one and emits an
equivalent Databricks notebook.

### `fixtures/`

`export_fixtures.sh` captures reconcile fixtures. Two flavors:

- **`Get*` procs** (return result sets, take `@LastCutoff`/`@NewCutoff`):
  the fixture is the proc's result set as CSV.
- **`Migrate*` procs** (INSERT/UPDATE into `Dimension.*` tables, no result set):
  the fixture is the target Dimension table state **after** executing the proc.

The Test agent compares the gold medallion tables against these fixtures to
prove the migration is correct.

## Usage

These scripts are normally invoked by `infra/azure/bootstrap.sh` after the
bacpac is imported. To run them manually:

```bash
# 1. Source your .env
set -a; . ./.env; set +a

# 2. (Re-)import the bacpac into Azure SQL
./legacy/wideworldimportersdw/import_azure_sql.sh

# 3. Export proc source
./legacy/procs/export_proc_source.sh

# 4. Export fixtures (NOTE: mutates the DB via Migrate* procs)
./legacy/fixtures/export_fixtures.sh
```
