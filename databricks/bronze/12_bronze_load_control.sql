-- 12_bronze_load_control.sql
-- Aggregate the per-table load_control rows into a summary view for the
-- dashboard and the Test agent. Pure metadata; no bronze data changes.

CREATE OR REPLACE VIEW edw_migration.ops.bronze_load_summary AS
SELECT
  table_name,
  batch_id,
  row_count,
  started_at,
  ended_at,
  status,
  COALESCE(row_count, 0) = 0 AS empty_load
FROM edw_migration.ops.load_control
WHERE table_name LIKE 'bronze.%';

SELECT 'bronze_load_control_ok' AS check_name,
       (SELECT COUNT(*) FROM edw_migration.ops.bronze_load_summary) AS bronze_loads;
