# Troubleshooting

Common failures when running the EDW migration demo, with the fastest fix.

---

## Azure SQL / Federation

### Federation smoke: `FAILED_JDBC.CONNECTION` or timeout

**Cause:** serverless DB is cold (auto-paused after ~15 min idle), or still
warming after resume.

**Fix:**

```bash
sqlcmd -S tcp:${AZ_SQL_SERVER}.database.windows.net,1433 \
  -U "${AZ_SQL_ADMIN}" -P "${AZ_SQL_PASSWORD}" \
  -d WideWorldImportersDW -Q "SELECT 1"
```

Wait ~30–60s after first resume, then re-run:

```bash
./agents/tools/run_sql.sh --file databricks/uc/02_federation_smoke.sql
```

`bootstrap.sh` already warms the DB; this matters for later sessions.

### Federation smoke: network / cannot connect

**Cause:** Free Edition (AWS-hosted) cannot reach Azure SQL without a broad
firewall rule; “Allow Azure services” is not enough.

**Fix:** Confirm firewall rule `AllowDatabricksDemo` (`0.0.0.0/0`) exists.
See [firewall.md](firewall.md). Tear down after the demo.

### Bacpac import fails / hash mismatch

**Fix:**

```bash
./legacy/wideworldimportersdw/download_bacpac.sh
# Expect SHA-256: 96e9b87dfe3665aefde12a2c4decb835982803470d7f224b988d8f512db2a6c5
```

Then re-run bootstrap (or only the import step if you know the server is up).

### Free allowance exhausted (`AutoPause` on limit)

**Cause:** 100k vCore-seconds/month used up. DB won’t accept useful work until
the monthly reset (or you use a different subscription).

**Mitigation:** Tear down unused free DBs; use [agents/samples](../agents/samples/README.md)
for offline Gate demos. See [limits.md](limits.md).

---

## Databricks CLI / bundle

### `databricks sql execute` not found

**Expected.** Use the Statement API wrapper:

```bash
./agents/tools/run_sql.sh --sql "SELECT 1"
./agents/tools/run_sql.sh --file path/to/file.sql
```

### Bundle validate/deploy: warehouse / variable errors

```bash
export BUNDLE_VAR_warehouse_id="$DATABRICKS_WAREHOUSE_ID"
databricks bundle validate -t dev
```

- Warehouse must be **serverless** (Free Edition).
- Paths in job YAML are relative to `databricks/jobs/` — do not “fix” them
  to repo-root absolute paths.

### Bundle run fails on a mid DAG task

Open the job run in the workspace UI; failed task logs show the SQL error.
Typical causes: cold federation (re-warm Azure), missing `ops` tables
(re-run `03_ops_and_views.sql`), or fixture stage before expectations were
built (`./legacy/fixtures/build_expectations.sh`).

### Dashboard missing after deploy

Confirm `databricks/jobs/dashboard.yml` is included from `databricks.yml` and
redeploy `-t dev`. Name: **`[dev] EDW Migration Agent Events`**.

---

## Cursor agents / hooks

### No rows in `ops.agent_events`

Checklist:

1. `.env` sourced (`DATABRICKS_HOST`, `DATABRICKS_TOKEN`, `DATABRICKS_WAREHOUSE_ID`).
2. Repo opened at the git root so `.cursor/hooks.json` applies.
3. Coordinator wrote `agents/out/CURRENT_RUN` (hooks resolve `run_id` from it).
4. Buffer file exists: `agents/out/<run_id>/events.buf.jsonl`.

Manual flush:

```bash
./.cursor/hooks/_flush_events.sh "$(cat agents/out/CURRENT_RUN)"
```

Logging hooks use `failClosed: false` — a flush failure does **not** stop the
agent run; events stay on disk.

### Gate fails repeatedly

Read blockers:

```bash
./agents/tools/render_manifest_table.py agents/out/<run_id>/migration_manifest.json
```

Each blocker is either an unconverted / blocked proc or a failed reconcile
check. Fix the underlying SQL or fixture, then re-kick the coordinator
(or increase `max_retries` in `context.json` — keep aligned with
`loop_limit` in hooks).

### Convert overwrote a baseline notebook

It shouldn’t: prompts say write to `databricks/converted/` when silver/gold
baselines exist. If a baseline was overwritten, restore from git and move the
agent draft under `databricks/converted/`.

### `jq: command not found` in hooks

Hooks parse payloads with **python3**. Install `jq` only if a local script
still calls it, or for ad-hoc JSON viewing — not required for the happy path.

---

## Reconcile / fixtures

### Reconcile fails on row counts

1. Confirm fixtures were exported after bacpac import
   (`legacy/fixtures/export_fixtures.sh` — note: Migrate* procs mutate the DB).
2. Rebuild expectations: `./legacy/fixtures/build_expectations.sh`.
3. Re-run the job (or at least `stage_fixtures` → `reconcile`).

### Offline sample expectation only

`sample_offline_city` (gte 1) always runs so reconcile has something to do
even without full fixture export. It alone does not prove a full migration.

---

## Still stuck?

1. Re-read [limits.md](limits.md) for Free Edition / free SQL constraints.  
2. Confirm you are on target `dev` with `BUNDLE_VAR_warehouse_id` set.  
3. Open an issue on the repo with the failing task name + redacted error text.
