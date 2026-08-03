# legacy/ — demo-pack source artifacts

Sample-estate assets for WideWorldImportersDW (demo pack). The **engine** discovers
tables/procs from whatever Azure SQL you connect; this folder holds the vendored
bacpac, exported T-SQL, and optional reconcile fixtures for the guided demo.

```text
legacy/
  wideworldimportersdw/   Vendored .bacpac + download_bacpac.sh (SHA pinned)
  procs/                  Exported / vendored T-SQL (Convert input)
  fixtures/               CSV snapshots + expectations for optional fixture reconcile
```

Also see [demo/wwi/README.md](../demo/wwi/README.md).

## `wideworldimportersdw/`

Microsoft sample EDW as a `.bacpac`, SHA-256 pinned. Bootstrap imports it with
`SqlPackage`. Details: [wideworldimportersdw/README.md](wideworldimportersdw/README.md).

## `procs/`

`export_proc_source.sh` dumps user procedures from the connected Azure SQL DB
(used by bootstrap and by `discover_inventory.py`). Vendored `Integration.*`
files let Convert work from git when a live export has not run yet; a live
export overwrites them.

Discovery does **not** hard-code this list — Assess builds the backlog from
whatever procs are exported / inventoried.

## `fixtures/`

`export_fixtures.sh` captures optional reconcile fixtures (can mutate DB via
`Migrate*` procs). `build_expectations.sh` regenerates `expectations.json` and
`databricks/tests/13_stage_fixture_expectations.sql` (catalog placeholder
`__UC_CATALOG__`).

Primary correctness for the engine is **generated** bronze-vs-source row-count
reconcile from inventory; fixtures are demo-pack enrichment.

## Manual usage

Normally via `make bootstrap` / `edw-demo-guide`. Standalone:

```bash
set -a; . ./.env; set +a
./legacy/wideworldimportersdw/download_bacpac.sh
./legacy/procs/export_proc_source.sh
./legacy/fixtures/export_fixtures.sh    # mutates DB
./legacy/fixtures/build_expectations.sh
```
