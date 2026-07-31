# legacy/ — source EDW artifacts for the migration demo

This directory holds everything that represents the **source** side of the
migration: the WideWorldImportersDW sample database, its stored-procedure
source, and the reconcile fixtures captured from running those procs.

```text
legacy/
  wideworldimportersdw/   WideWorldImportersDW-Standard.bacpac + download_bacpac.sh
  procs/                  One .sql file per [Integration]/* proc (the migration teaching surface)
  fixtures/               CSV snapshots used by the Test agent to reconcile gold tables
```

## Layout

### `wideworldimportersdw/`

The Microsoft sample EDW as a `.bacpac`. `download_bacpac.sh` **downloads**
it from Microsoft's SQL Server samples release on first use (not committed
as a binary — ~21 MB). Pin `EXPECTED_SHA256` in that script after the first
download. Bootstrap then runs `SqlPackage /a:Import` against Azure SQL.

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
./legacy/wideworldimportersdw/download_bacpac.sh

# 3. Export proc source
./legacy/procs/export_proc_source.sh

# 4. Export fixtures (NOTE: mutates the DB via Migrate* procs)
./legacy/fixtures/export_fixtures.sh
```
