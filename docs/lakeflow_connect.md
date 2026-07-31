# Why Lakehouse Federation, not Lakeflow Connect

This demo uses **Lakehouse Federation** to read from Azure SQL. It does not
use **Lakeflow Connect**. Here is why.

## What each is

- **Lakehouse Federation** is a Unity Catalog feature that lets you query
  external databases (Azure SQL, Postgres, MySQL, etc.) in place from a
  serverless SQL warehouse, without moving data. You create a `CONNECTION`,
  a `FOREIGN CATALOG`, and then `SELECT` from the foreign tables as if they
  were Unity Catalog tables.
- **Lakeflow Connect** (formerly "Lakehouse Federation via Connect") is a
  separate product that uses a gateway process running on a Databricks
  cluster to fan out queries to external systems. It supports more sources
  and pushdown than Federation, but it requires a **classic cluster** to
  host the gateway.

## Why Federation for this demo

1. **Free Edition has no classic clusters.** Lakeflow Connect's gateway
   runs on a classic cluster. Free Edition is serverless-only, so Lakeflow
   Connect cannot run.
2. **Federation runs on serverless SQL warehouses.** Free Edition provides
   serverless SQL warehouses, which is exactly what Federation needs.
3. **The use case fits.** We only need to read from Azure SQL (assess and
   reconcile) and then materialize managed tables in Unity Catalog.
   Federation's read-only pushdown is sufficient. We do not need
   write-back, CDC, or the broader source matrix that Lakeflow Connect
   supports.
4. **Simpler setup.** Federation is pure SQL (`CREATE CONNECTION`,
   `CREATE FOREIGN CATALOG`). No gateway process, no cluster policy, no
   extra moving parts.

## When you would use Lakeflow Connect instead

- You are on a paid Databricks tier with classic clusters.
- You need a source that Federation does not support (check the current
  Federation vs. Lakeflow Connect source matrix).
- You need write-back or CDC to the external system.
- You need heavier pushdown than Federation provides.

For this demo on Free Edition, Federation is the right tool.
