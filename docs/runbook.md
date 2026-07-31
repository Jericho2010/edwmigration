# Runbook

End-to-end operator guide for the EDW → Databricks AI-assisted migration demo.

**Audience:** anyone running the demo for real (SE, prospect engineer, partner).  
**Time:** ~45 minutes first run; ~20 minutes if Azure is already provisioned.  
**Cost:** $0 on Free Edition + Azure SQL free offer when you tear down Azure after.

Related: [prerequisites](prerequisites.md) · [architecture](architecture.md) · [demo script](demo-script.md) · [troubleshooting](troubleshooting.md)

---

## 0. Prerequisites

Complete [prerequisites.md](prerequisites.md). You need:

| Required | Optional |
|---|---|
| `az`, `SqlPackage`, `sqlcmd`, `databricks` CLI, `python3`, Cursor | `jq` (pretty-print JSON) |
| Databricks Free Edition workspace + PAT + serverless warehouse ID | — |
| Azure subscription (for the free SQL DB) | — |

---

## 1. Configure

```bash
git clone https://github.com/Jericho2010/edwmigration.git
cd edwmigration
cp infra/azure/.env.example .env
$EDITOR .env
```

Fill in at least:

| Variable | Purpose |
|---|---|
| `AZ_SUBSCRIPTION_ID` | Azure subscription |
| `AZ_SQL_SERVER` | Globally unique SQL logical server name |
| `AZ_SQL_PASSWORD` | Strong admin password (never commit) |
| `DATABRICKS_HOST` | Workspace URL |
| `DATABRICKS_TOKEN` | PAT |
| `DATABRICKS_WAREHOUSE_ID` | Serverless SQL warehouse ID |

```bash
set -a; . ./.env; set +a
```

---

## 2. Provision Azure SQL + load the EDW

The WideWorldImportersDW `.bacpac` is **vendored** in
`legacy/wideworldimportersdw/` (SHA-256 pinned). `download_bacpac.sh` only
runs if the file is missing or the hash does not match.

```bash
./infra/azure/bootstrap.sh --dry-run   # validate without creating resources
./infra/azure/bootstrap.sh             # ~10 min
```

What bootstrap does:

1. Creates resource group + SQL logical server.
2. Creates the free-offer database (`AutoPause` on limit exhaustion).
3. Creates firewall rules (your client IP + `0.0.0.0/0` for Free Edition egress — see [firewall.md](firewall.md)).
4. Imports the vendored bacpac via `SqlPackage`.
5. Warms the serverless DB (cold pause would break federation).
6. Exports proc source → `legacy/procs/*.sql`.
7. Exports reconcile fixtures → `legacy/fixtures/*.csv` and regenerates expectations.
8. Creates Databricks secrets scope `edw-migration` and stores the SQL password.
9. Smoke-tests the DB.

---

## 3. Bootstrap Unity Catalog + Federation

```bash
./agents/tools/render_federation_sql.sh > /tmp/01_federation_setup.rendered.sql
./agents/tools/run_sql.sh --file /tmp/01_federation_setup.rendered.sql
./agents/tools/run_sql.sh --file databricks/uc/03_ops_and_views.sql
./agents/tools/run_sql.sh --file databricks/uc/02_federation_smoke.sql
```

Creates:

- Managed catalog `edw_migration` with schemas `source_fed`, `bronze`, `silver`, `gold`, `ops`
- Federation connection `azure_sql_edw` + foreign catalog `wwi_dw_fed`
- Minimal `GRANT`s for `account users`
- `ops.*` tables including `ops.agent_events` (observability sink)
- `source_fed.*` convenience views over the foreign catalog

`run_sql.sh` uses the Databricks Statement Execution API
(`databricks api post /api/2.0/sql/statements`). There is **no**
`databricks sql execute` CLI command.

---

## 4. Deploy and run the medallion job

```bash
# Warehouse ID as a DAB variable (required)
export BUNDLE_VAR_warehouse_id="$DATABRICKS_WAREHOUSE_ID"

databricks bundle validate -t dev
databricks bundle deploy -t dev
databricks bundle run edw_migration_medallion -t dev
```

### Job DAG (what runs)

SQL paths in `databricks/jobs/*.yml` are **relative to that YAML file**.

```text
federation_smoke
  ├─► bronze_dims ─┬─► silver_dims ──────────────┬─► gold_stock / gold_city
  │                └─► silver_customer_scd2 ─────┴─► gold_customer_current
  ├─► bronze_facts ─┐
  │                 └─► silver_fact_sale ─┬─► gold_daily_sales
  │                                      └─► metric_daily_sales
  └─► stage_fixtures
          │
          ▼
  (all gold + fixtures + metric) → reconcile → lineage_check
```

Peak fan-out stays under Free Edition’s **max 5 concurrent tasks**.  
The same `bundle deploy` publishes the AI/BI dashboard
`[dev] EDW Migration Agent Events` (no manual Lakeview import).

### Fixture expectations

Bootstrap regenerates expectations. To rebuild manually after re-exporting fixtures:

```bash
./legacy/fixtures/build_expectations.sh
# → legacy/fixtures/expectations.json
# → databricks/tests/13_stage_fixture_expectations.sql
```

The job stages expectations into `ops.fixture_expectations`; reconcile
compares gold/bronze counts. Offline sample expectation `sample_offline_city`
(gte 1) always runs.

---

## 5. Open the observability dashboard

After deploy, open **`[dev] EDW Migration Agent Events`** in Databricks AI/BI.

It queries `edw_migration.ops.agent_events`. The table is empty until the
Cursor agent workflow runs (next step) — hooks write events on lifecycle
transitions.

---

## 6. Run the agent workflow in Cursor

1. Open this repo in Cursor (so `.cursor/agents/` and `.cursor/hooks.json` load).
2. Launch the **`edw-coordinator`** subagent.
3. Kickoff message (copy/paste):

   > Start an EDW migration run. Scope: Fact.Sale, Fact.Stockholding,
   > Dimension.Customer, Dimension.City, Dimension.StockItem.
   > Migrate the Integration.* procs.

4. The coordinator will:
   - Mint a `run_id`, write `agents/out/<run_id>/context.json`, and write
     the bare id to `agents/out/CURRENT_RUN` (hooks resolve `run_id` from here —
     Cursor payloads do not include it).
   - Delegate **Assess** → returns backlog JSON → coordinator persists it.
   - For each backlog item, delegate **Convert** → writes under
     `databricks/converted/` when a baseline silver/gold file already exists
     (does not overwrite the job DAG baselines).
   - Delegate **Test** → reconcile report JSON.
   - Delegate **Gate** → migration manifest (pass/fail + blockers).
   - On gate=fail with retries left, re-delegate Convert (`loop_limit: 2` /
     `max_retries: 2`).

5. Watch `ops.agent_events` populate in the dashboard as hooks fire.

6. When complete:

```bash
./agents/tools/render_manifest_table.py agents/out/<run_id>/migration_manifest.json
# or: python3 -m json.tool agents/out/<run_id>/migration_manifest.json
```

### Offline Gate demo (no Azure / no live agents)

```bash
RUN_ID=00000000-0000-4000-8000-000000000001
mkdir -p "agents/out/${RUN_ID}"
cp agents/samples/run/* "agents/out/${RUN_ID}/"
echo "$RUN_ID" > agents/out/CURRENT_RUN
./agents/tools/render_manifest_table.py "agents/out/${RUN_ID}/migration_manifest.json"
```

See [agents/samples/README.md](../agents/samples/README.md).

---

## 7. Inspect the results

| Surface | What to look at |
|---|---|
| Bronze | `edw_migration.bronze.*` — 1:1 land from source |
| Silver | `edw_migration.silver.*` — conformed types, SCD2 customer |
| Gold | `edw_migration.gold.*` — marts replacing Integration.* outcomes |
| Metric view | Daily sales metric (AI/BI-friendly) |
| Ops | `load_control`, `migration_backlog`, `proc_conversion_map`, `reconcile_results`, `agent_events`, `fixture_expectations` |
| Agent output | `agents/out/<run_id>/` + `databricks/converted/` |
| Manifest | `migration_manifest.json` — ship / no-ship |

---

## 8. Tear down

```bash
./infra/azure/teardown.sh
# Optional — remove the secrets scope:
databricks secrets delete-scope edw-migration
```

Teardown deletes the Azure resource group (server, DB, firewall).  
Databricks objects remain; clean slate:

```sql
DROP CATALOG edw_migration CASCADE;
DROP CONNECTION azure_sql_edw;
-- foreign catalog wwi_dw_fed drops with the connection
```

---

## Next failures

See [troubleshooting.md](troubleshooting.md) for cold DB, firewall, bundle,
hooks, and gate failures.
