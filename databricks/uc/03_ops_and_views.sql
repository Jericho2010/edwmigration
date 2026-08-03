-- 03_ops_and_views.sql — operational tables for the migration engine.
-- Placeholders: __UC_CATALOG__ (render_sql.sh). Idempotent.

CREATE TABLE IF NOT EXISTS __UC_CATALOG__.ops.load_control (
  table_name      STRING       NOT NULL,
  batch_id        STRING       NOT NULL,
  row_count       BIGINT,
  started_at      TIMESTAMP    NOT NULL,
  ended_at        TIMESTAMP,
  status          STRING       NOT NULL
)
COMMENT 'Per-table load audit for bronze landings';

CREATE TABLE IF NOT EXISTS __UC_CATALOG__.ops.migration_inventory (
  run_id            STRING,
  object_type       STRING       NOT NULL,  -- 'table' | 'proc'
  source_schema     STRING       NOT NULL,
  source_name       STRING       NOT NULL,
  landing_name      STRING,                  -- snake_case bronze name (tables)
  skip              BOOLEAN      NOT NULL DEFAULT false,
  skip_reason       STRING,
  discovered_at     TIMESTAMP    NOT NULL
)
COMMENT 'Discovered base tables and user procs (source of truth for land/Gate)';

CREATE TABLE IF NOT EXISTS __UC_CATALOG__.ops.migration_backlog (
  item_id         STRING       NOT NULL,
  legacy_proc     STRING       NOT NULL,
  classification  STRING       NOT NULL,
  reads           STRING,
  writes          STRING,
  target_layer    STRING,
  target_path     STRING,
  priority        STRING,
  risk_flags      STRING,
  status          STRING       NOT NULL,
  updated_at      TIMESTAMP    NOT NULL
)
COMMENT 'Assess backlog of procs to convert';

ALTER TABLE __UC_CATALOG__.ops.migration_backlog
  DROP CONSTRAINT IF EXISTS migration_backlog_pk;
ALTER TABLE __UC_CATALOG__.ops.migration_backlog
  ADD CONSTRAINT migration_backlog_pk PRIMARY KEY (item_id) NOT ENFORCED;

CREATE TABLE IF NOT EXISTS __UC_CATALOG__.ops.proc_conversion_map (
  legacy_proc     STRING       NOT NULL,
  target_path     STRING       NOT NULL,
  status          STRING       NOT NULL,
  updated_at      TIMESTAMP    NOT NULL
)
COMMENT 'Convert agent record of converted procs';

CREATE TABLE IF NOT EXISTS __UC_CATALOG__.ops.reconcile_results (
  check_id        STRING       NOT NULL,
  table_name      STRING       NOT NULL,
  expected        STRING,
  actual          STRING,
  delta           STRING,
  result          STRING       NOT NULL,
  run_id          STRING       NOT NULL,
  ts              TIMESTAMP    NOT NULL
)
COMMENT 'Reconcile check outcomes';

CREATE TABLE IF NOT EXISTS __UC_CATALOG__.ops.fixture_expectations (
  fixture_name    STRING       NOT NULL,
  target_table    STRING       NOT NULL,
  metric          STRING       NOT NULL,
  expected        BIGINT,
  compare         STRING       NOT NULL,
  notes           STRING
)
COMMENT 'Optional demo-pack fixture expectations';

CREATE TABLE IF NOT EXISTS __UC_CATALOG__.ops.migration_manifest_current (
  run_id          STRING       NOT NULL,
  gate            STRING       NOT NULL,
  tables_total    INT,
  tables_landed   INT,
  procs_total     INT,
  procs_converted INT,
  summary_json    STRING,
  updated_at      TIMESTAMP    NOT NULL
)
COMMENT 'Latest Gate manifest mirror for Dashboard/Genie';

CREATE TABLE IF NOT EXISTS __UC_CATALOG__.ops.agent_events (
  run_id          STRING,
  agent           STRING       NOT NULL,
  event           STRING       NOT NULL,
  tool            STRING,
  detail          STRING,
  ts              TIMESTAMP    NOT NULL
)
USING DELTA
CLUSTER BY (run_id, ts)
COMMENT 'Agent lifecycle events (observability)'
TBLPROPERTIES ('delta.enableChangeDataFeed' = 'true');

SELECT 'ops_and_views_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.ops.agent_events) AS agent_events_rows;
