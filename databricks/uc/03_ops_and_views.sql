-- 03_ops_and_views.sql
-- Create the operational tables that the agents and the medallion pipeline
-- read/write. Run AFTER 01_federation_setup.sql (which creates the catalog and
-- schemas). Idempotent (CREATE TABLE IF NOT EXISTS).
--
-- Tables:
--   ops.load_control        — per-table load audit (bronze)
--   ops.migration_backlog   — Assess agent's inventory of procs to migrate
--   ops.proc_conversion_map — Convert agent's record of converted procs
--   ops.reconcile_results   — Test agent's reconcile check outcomes
--   ops.agent_events        — Cursor hooks write structured events here (observability)
--
-- Run via:
--   ./agents/tools/run_sql.sh --file databricks/uc/03_ops_and_views.sql

-- ---------------------------------------------------------------------------
-- ops.load_control
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS edw_migration.ops.load_control (
  table_name      STRING       NOT NULL,
  batch_id        STRING       NOT NULL,
  row_count       BIGINT,
  started_at      TIMESTAMP    NOT NULL,
  ended_at        TIMESTAMP,
  status          STRING       NOT NULL  -- 'running' | 'ok' | 'failed'
)
COMMENT 'Per-table load audit for bronze landings';

-- ---------------------------------------------------------------------------
-- ops.migration_backlog
-- Written by the coordinator on behalf of the Assess agent.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS edw_migration.ops.migration_backlog (
  item_id         STRING       NOT NULL,
  legacy_proc     STRING       NOT NULL,
  classification  STRING       NOT NULL,  -- 'get' | 'migrate' | 'other'
  reads           STRING,                  -- comma-separated source tables
  writes          STRING,                  -- comma-separated target tables
  target_layer    STRING,                  -- 'silver' | 'gold'
  target_path     STRING,                  -- e.g. databricks/gold/30_mart_daily_sales.sql
  priority        STRING,                  -- 'high' | 'medium' | 'low'
  risk_flags      STRING,                  -- comma-separated risk tags
  status          STRING       NOT NULL,  -- 'pending' | 'in_progress' | 'converted' | 'tested' | 'done'
  updated_at      TIMESTAMP    NOT NULL
)
COMMENT 'Assess agent inventory of procs to migrate';
ALTER TABLE edw_migration.ops.migration_backlog
  DROP CONSTRAINT IF EXISTS migration_backlog_pk;

ALTER TABLE edw_migration.ops.migration_backlog
  ADD CONSTRAINT migration_backlog_pk PRIMARY KEY (item_id) NOT ENFORCED;

-- ---------------------------------------------------------------------------
-- ops.proc_conversion_map
-- Written by the coordinator on behalf of the Convert agent.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS edw_migration.ops.proc_conversion_map (
  legacy_proc     STRING       NOT NULL,
  target_path     STRING       NOT NULL,
  status          STRING       NOT NULL,  -- 'draft' | 'review' | 'final'
  updated_at      TIMESTAMP    NOT NULL
)
COMMENT 'Convert agent record of converted procs';

-- ---------------------------------------------------------------------------
-- ops.reconcile_results
-- Written by the coordinator on behalf of the Test agent.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS edw_migration.ops.reconcile_results (
  check_id        STRING       NOT NULL,
  table_name      STRING       NOT NULL,
  expected        STRING,
  actual          STRING,
  delta           STRING,
  result          STRING       NOT NULL,  -- 'pass' | 'fail'
  run_id          STRING       NOT NULL,
  ts              TIMESTAMP    NOT NULL
)
COMMENT 'Test agent reconcile check outcomes';

-- ---------------------------------------------------------------------------
-- ops.agent_events
-- Written by Cursor hooks (log_event.sh, on_subagent_stop.sh) for observability.
-- The AI/BI dashboard (databricks/dashboards/agent_events.lvdash.json) reads
-- from this table.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS edw_migration.ops.agent_events (
  run_id          STRING,
  agent           STRING       NOT NULL,  -- 'coordinator' | 'assess' | 'convert' | 'test' | 'gate'
  event           STRING       NOT NULL,  -- 'subagentStart' | 'subagentStop' | 'afterFileEdit' | ...
  tool            STRING,                  -- 'Read' | 'Edit' | 'Shell' | 'MCP' | null
  detail          STRING,                  -- free-form context
  ts              TIMESTAMP    NOT NULL
)
USING DELTA
CLUSTER BY (run_id, ts)
COMMENT 'Cursor hook event log (observability sink for the agent workflow)'
TBLPROPERTIES ('delta.enableChangeDataFeed' = 'true');

-- NOTE: source_fed is intentionally NOT touched here. Online it holds
-- federation views created by 01_federation_setup.sql; offline it holds
-- seeded Delta tables from databricks/offline/. Recreating views here would
-- clobber the offline seed (and fail without the foreign catalog).

-- ---------------------------------------------------------------------------
-- Done
-- ---------------------------------------------------------------------------
SELECT 'ops_and_views_ok' AS check_name,
       (SELECT COUNT(*) FROM edw_migration.ops.agent_events) AS agent_events_rows;
