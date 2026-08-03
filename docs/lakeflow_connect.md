# Why Lakehouse Federation, not Lakeflow Connect

This product uses **Lakehouse Federation** to read from Azure SQL. It does not
use **Lakeflow Connect**.

## What each is

- **Lakehouse Federation** — Unity Catalog `CONNECTION` + foreign catalog;
  query external databases from a serverless SQL warehouse without moving data
  first. Engine land then materializes managed Delta in your catalog.
- **Lakeflow Connect** — managed ingestion / gateway patterns that typically
  need classic compute for the gateway. Broader source matrix and CDC options,
  but not available on Databricks Free Edition.

## Why Federation here

1. **Free Edition has no classic clusters** → Connect gateway cannot run.
2. **Federation runs on serverless SQL warehouses** (demo path).
3. **Fit:** read Azure SQL for discover / land / reconcile; write managed UC
   tables. No write-back or CDC in v1.
4. **Simple DDL:** `CREATE CONNECTION` + `CREATE FOREIGN CATALOG` (+ secrets).

## When you would use Lakeflow Connect instead

- Paid Databricks tier with classic clusters (or Connect features you need).
- Source types Federation does not support.
- Write-back or CDC into / from the external system.
- Heavier pushdown than Federation provides.

For the guided Free Edition demo and the Azure SQL engine path, Federation is
the right tool. See also [limits.md](limits.md).
