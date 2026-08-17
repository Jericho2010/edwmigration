# Demo pack — WideWorldImportersDW

Optional sample estate for the guided demo. **Not part of the migration engine.**

## What lives here vs elsewhere

| Asset | Location |
|---|---|
| Free Azure SQL bootstrap | [`infra/azure/`](../../infra/azure/) |
| Bacpac download / import | [`legacy/wideworldimportersdw/`](../../legacy/wideworldimportersdw/) |
| Exported proc sources / fixtures | Vendored teaching procs: [`legacy/procs/`](../../legacy/procs/). Live dumps: `agents/out/<run_id>/procs` or `legacy/procs/.export/` (gitignored). Fixture scripts: [`legacy/fixtures/`](../../legacy/fixtures/) (CSVs local/gitignored). |
| Known-good silver/gold for WWI patterns | [`databricks/silver/`](../../databricks/silver/), [`databricks/gold/`](../../databricks/gold/) (Convert may refresh) |

## How to run

Prefer typing **`start`** → **1** (or **`edw-demo-guide`**). Log in when preflight asks.

Or: `make materialize-demo && make demo`

## Extensibility proof

Add tables or stored procedures to the Azure SQL sample database and re-run Assess — inventory grows automatically; no engine code changes.
