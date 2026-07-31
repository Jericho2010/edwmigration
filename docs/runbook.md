# Runbook

End-to-end run of the EDW → Databricks migration demo, including the agent
workflow.

## 0. Prerequisites

Complete [prerequisites.md](prerequisites.md) first. You need:
- `az`, `SqlPackage`, `sqlcmd`, `databricks`, `jq`, `python3`, Cursor
- A Databricks Free Edition workspace URL + PAT
- An Azure subscription

## 1. Configure

```bash
git clone <this repo>
cd edwmigration
cp infra/azure/.env.example .env
$EDITOR .env
# Fill in:
#   AZ_SUBSCRIPTION_ID, AZ_SQL_SERVER (globally unique), AZ_SQL_PASSWORD
#   DATABRICKS_HOST, DATABRICKS_TOKEN, DATABRICKS_WAREHOUSE_ID
set -a; . ./.env; set +a
```

## 2. Provision Azure SQL + load the EDW

```bash
./infra/azure/bootstrap.sh --dry-run   # validate without spending
./infra/azure/bootstrap.sh             # ~10 min
```

What this does:
1. Creates RG + SQL logical server.
2. Creates the free-offer DB (`AutoPause` on limit).
3. Creates firewall rules (client IP + `0.0.0.0/0` for Databricks egress).
4. Imports the WWI bacpac via `SqlPackage`.
5. Warms up the (now-cold) serverless DB.
6. Exports proc source to `legacy/procs/*.sql`.
7. Exports reconcile fixtures to `legacy/fixtures/*.csv`.
8. Creates the Databricks secrets scope `edw-migration` and stores the SQL
   password.
9. Smoke-tests the DB.

## 3. Bootstrap Unity Catalog + Federation

```bash
./agents/tools/render_federation_sql.sh > /tmp/01_federation_setup.rendered.sql
./agents/tools/run_sql.sh --file /tmp/01_federation_setup.rendered.sql
./agents/tools/run_sql.sh --file databricks/uc/03_ops_and_views.sql
./agents/tools/run_sql.sh --file databricks/uc/02_federation_smoke.sql
```

This creates:
- The `edw_migration` catalog with `source_fed`, `bronze`, `silver`, `gold`,
  `ops` schemas.
- The federation connection `azure_sql_edw` and foreign catalog `wwi_dw_fed`.
- Minimal `GRANT`s for `account users`.
- The `ops.*` tables including `ops.agent_events` (the observability sink).
- The `source_fed.*` convenience views.

`run_sql.sh` uses the Databricks Statement Execution API (`databricks api post
/api/2.0/sql/statements`). There is no `databricks sql execute` CLI command.

## 4. Validate, deploy, and run the medallion

```bash
# Required: warehouse ID as a bundle variable (env convention from DABs)
export BUNDLE_VAR_warehouse_id="$DATABRICKS_WAREHOUSE_ID"

databricks bundle validate -t dev
databricks bundle deploy -t dev
databricks bundle run edw_migration_medallion -t dev
```

The job DAG fans out where safe (under Free Edition's max 5 concurrent tasks):
federation smoke → bronze dims/facts → silver → gold marts → reconcile.
The AI/BI dashboard is deployed by the same `bundle deploy` (no manual import).

## 5. Open the observability dashboard

After deploy, open the dashboard named
`[dev] EDW Migration Agent Events` in Databricks AI/BI Dashboards.
It queries `edw_migration.ops.agent_events`.

Initially the table is empty — the hooks only write events when the agent
workflow runs (next step).

## 5b. Fixture expectations

After `export_fixtures.sh` (part of bootstrap), expectations are regenerated:

```bash
./legacy/fixtures/build_expectations.sh
# Writes legacy/fixtures/expectations.json and
# databricks/tests/13_stage_fixture_expectations.sql
```

The medallion job stages these into `ops.fixture_expectations` and reconcile
compares gold/bronze counts. Offline sample expectation
`sample_offline_city` (gte 1) always runs.

## 6. Run the agent workflow in Cursor

1. Open this repo in Cursor.
2. Launch the `edw-coordinator` subagent (via the chat panel or the
   subagent picker).
3. Send a kickoff message, e.g.:
   > Start an EDW migration run. Scope: Fact.Sale, Fact.Stockholding,
   > Dimension.Customer, Dimension.City, Dimension.StockItem. Migrate the
   > Integration.* procs.
4. The coordinator will:
   - Generate a `run_id` and write `agents/out/<run_id>/context.json`.
   - Launch `edw-assess` → it returns a migration backlog.
   - For each backlog item, launch `edw-convert` → it writes a notebook to
     `databricks/silver|gold/`.
   - Launch `edw-test` → it runs `reconcile.sql` and returns a report.
   - Launch `edw-gate` → it returns a manifest (pass/fail + blockers).
   - If gate=fail and retries remain, re-delegate to convert.
5. Watch `ops.agent_events` populate in the dashboard as the hooks fire on
   each lifecycle event.
6. When the run completes, read the manifest:
   ```bash
   cat agents/out/<run_id>/migration_manifest.json | jq .
   ```
   Or render it as a table:
   ```bash
   ./agents/tools/render_manifest_table.py agents/out/<run_id>/migration_manifest.json
   ```

## 7. Inspect the results

- **Bronze:** `edw_migration.bronze.*` — 1:1 land from source.
- **Silver:** `edw_migration.silver.*` — conformed, SCD2 on customer.
- **Gold:** `edw_migration.gold.*` — marts replacing the legacy procs.
- **Ops:** `edw_migration.ops.*` — load_control, migration_backlog,
  proc_conversion_map, reconcile_results, agent_events.
- **Manifest:** `agents/out/<run_id>/migration_manifest.json` — the final
  ship/no-ship decision.

## 8. Tear down

```bash
./infra/azure/teardown.sh
# Optionally remove the Databricks secrets scope:
databricks secrets delete-scope edw-migration
```

This deletes the entire Azure resource group (server, DB, firewall rules).
The Databricks catalog `edw_migration` and foreign catalog `wwi_dw_fed`
remain — drop them manually if you want a clean slate:

```sql
DROP CATALOG edw_migration CASCADE;
DROP CONNECTION azure_sql_edw;
-- wwi_dw_fed is dropped implicitly when the connection is dropped.
```

## Troubleshooting

- **Federation smoke fails with `FAILED_JDBC.CONNECTION`:** the Azure SQL DB
  is cold (auto-paused). Warm it up:
  ```bash
  sqlcmd -S tcp:<server>.database.windows.net,1433 -U <admin> -P <pass> -d WideWorldImportersDW -Q "SELECT 1"
  ```
  Then re-run the smoke.
- **Federation smoke fails with network error:** Free Edition outbound is
  restricted. Confirm the `AllowDatabricksDemo` firewall rule (`0.0.0.0/0`)
  exists. See [firewall.md](firewall.md).
- **`databricks bundle deploy` fails:** ensure `DATABRICKS_WAREHOUSE_ID` is
  set in `.env` and the warehouse is running.
- **Hook flush fails:** events remain buffered in
  `agents/out/<run_id>/events.buf.jsonl`. The run continues (failClosed:
  false on logging hooks). Inspect the buffer or re-flush manually:
  ```bash
  ./.cursor/hooks/_flush_events.sh <run_id>
  ```
- **Gate fails repeatedly:** read the blockers in the manifest. Each blocker
  points to either an unconverted proc or a failed reconcile check. Re-run
  the coordinator after fixing the underlying issue (or increase
  `max_retries` in `context.json`).
