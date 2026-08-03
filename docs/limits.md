# Limitations

Designed for free tiers where possible. Constraints shape the engine and the guided demo.

## Databricks Free Edition

- **Serverless compute only.** No classic clusters → Lakehouse Federation, not Lakeflow Connect ([lakeflow_connect.md](lakeflow_connect.md)).
- **Restricted outbound internet.** Azure SQL (`*.database.windows.net`) is typically reachable; arbitrary hosts may not be. Federation failures: check firewall ([firewall.md](firewall.md)).
- **Max 5 concurrent job tasks.** The medallion job must keep peak concurrency ≤ 5.
- **No classic SQL warehouses.** `DATABRICKS_WAREHOUSE_ID` must be serverless.
- **CLI:** dashboard `dataset_catalog` needs Databricks CLI ≥ 0.281.0 (0.292+ preferred).

## Azure SQL Database free offer (demo pack)

- **100,000 vCore-seconds / month** per subscription. Bacpac import is a few hundred vCore-seconds.
- **32 GB data / 32 GB backup** per DB. WWI Standard is well under.
- **Up to 10 free DBs** per subscription; first free DB locks the region (default `eastus`).
- **`AutoPause`** on limit exhaustion and after ~15 min idle — cold DB breaks federation until warmed.
- **`.bacpac` only** (no `.bak` restore) via SqlPackage.

## Engine scope (by design)

- **Source:** Azure SQL / SQL Server Federation only (for now).
- **Land objects:** base **tables** only (not views).
- **Full-auto discovery:** all visible base tables + user procs. If `tables_total > 200`, the coordinator warns and asks for confirm before land.
- **Batch full-refresh** bronze land (`CREATE OR REPLACE TABLE AS SELECT`). No CDC/streaming in v1.
- **Auth:** PAT supported now; OAuth (`databricks auth login`) is the enterprise target state.

## Out of scope

- Multi-cloud source connectors in the engine (CONNECTION types beyond SQLSERVER)
- Lakeflow Connect / classic clusters
- Lakebridge invocation (comparison only — [lakebridge.md](lakebridge.md))
- Offline / seeded-source mode (removed)
- Production SLAs, multi-region DR, cost optimization

## Extending

See [CONTRIBUTING.md](../CONTRIBUTING.md). Keep WWI object names out of the core engine; put sample-estate content under `demo/wwi/`, `infra/azure/`, or `legacy/`.
