# Demo pack — WideWorldImportersDW

Optional sample estate for the guided demo. **Not part of the migration engine.**

## What lives here vs elsewhere

| Asset | Location |
|---|---|
| Free Azure SQL bootstrap | [`infra/azure/`](../../infra/azure/) |
| Bacpac download / import | [`legacy/wideworldimportersdw/`](../../legacy/wideworldimportersdw/) |
| Exported proc sources / fixtures | Vendored teaching procs: [`legacy/procs/`](../../legacy/procs/). Live dumps: `agents/out/<run_id>/procs` or `legacy/procs/.export/` (gitignored). Fixture scripts: [`legacy/fixtures/`](../../legacy/fixtures/) (CSVs local/gitignored). |
| WWI silver/gold **reference** (not executed) | [`reference/silver/`](reference/silver/), [`reference/gold/`](reference/gold/) |

`reference/` is for humans debugging Convert. Coordinator and Convert **must not** copy these files into `databricks/silver|gold` or into the job. Track A bootstraps the bacpac as the **source**; gold marts exist only if Convert writes them from inventory/procs.

## How to run

Prefer typing **`start`** → **1** (or **`edw-demo-guide`**). Log in when preflight asks.

Or: `make materialize-demo && make demo`

## Extensibility proof

Point the engine at this bacpac **or any other** Azure SQL / MySQL database. Inventory, land, Assess, Convert, and job wiring are source-driven. No engine code changes for extra tables or procs.
