# Limitations

This demo is designed to run entirely within free tiers. Both have
constraints that shape the design.

## Databricks Free Edition

- **Serverless compute only.** No classic clusters. This rules out Lakeflow
  Connect (which needs a classic cluster for the gateway). We use Lakehouse
  Federation instead, which runs on serverless SQL warehouses.
- **Restricted outbound internet.** Free Edition limits egress to a small
  allowlist of trusted domains. Azure SQL (`*.database.windows.net`) is
  reachable, but arbitrary external endpoints may not be. If a federation
  query fails with a network error, confirm the Azure SQL firewall allows
  `0.0.0.0/0` (see [firewall.md](firewall.md)).
- **Max 5 concurrent job tasks.** The medallion job
  (`databricks/jobs/edw_migration_medallion.yml`) is sequential, so it stays
  well under this limit. If you add parallel tasks, keep the total under 5.
- **One active Lakeflow pipeline per type.** Not a constraint for this demo
  (we use a Lakeflow Job, not a pipeline), but worth knowing if you extend.
- **No classic SQL warehouses.** Only serverless. The `DATABRICKS_WAREHOUSE_ID`
  in `.env` must point to a serverless SQL warehouse (2X-Small is fine).
- **Workspace size / user limits.** See the Free Edition terms for current
  limits.

## Azure SQL Database free offer

- **100,000 vCore-seconds per month** per subscription. The bacpac import
  (~5 min on a Gen5 1-vCore serverless) consumes roughly 300 vCore-seconds,
  leaving plenty for the demo. Re-running bootstrap many times in a month
  could exhaust the allowance.
- **32 GB data per database.** WideWorldImportersDW-Standard is ~3.5 GB,
  well under the limit.
- **32 GB backup per database.** Auto-pauses and auto-scales; not a concern
  for this demo.
- **Up to 10 free databases per subscription.** One demo DB is fine.
- **First free DB locks the region.** All free DBs on a subscription must be
  in the same region as the first one. Pick a region up front (we default to
  `eastus`).
- **`AutoPause` on limit exhaustion.** When the free allowance is exhausted,
  the DB auto-pauses instead of charging. It resumes on the next query
  (after a warm-up delay).
- **Serverless auto-pause after 15 min of inactivity.** A cold DB will fail
  the federation smoke test with a JDBC connection error. `bootstrap.sh`
  warms the DB before the smoke; if you skip bootstrap, run a `SELECT 1` via
  `sqlcmd` first.
- **Cannot restore a `.bak`.** The free offer does not support `.bak`
  restore. We import a `.bacpac` via `SqlPackage` instead.

## What this demo does NOT cover

- **Real-time / CDC ingestion.** The medallion is full-refresh
  (`CREATE OR REPLACE TABLE AS SELECT`). Incremental/CDC patterns are out of
  scope.
- **Streaming.** No Structured Streaming or Auto Loader. The source is a
  batch EDW.
- **Production-grade orchestration.** The job is a single sequential
  Lakeflow Job. No retries, no SLAs, no alerting beyond the reconcile checks.
- **Multi-region / DR.** Single region, single workspace.
- **Cost optimization.** The demo targets $0. Production cost optimization
  (photon, cluster policies, spot, etc.) is out of scope.

## Extending the demo

See [CONTRIBUTING.md](../CONTRIBUTING.md) for how to add new proc patterns,
new stage agents, or new reconcile checks.
