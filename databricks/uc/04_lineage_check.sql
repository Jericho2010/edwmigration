-- 04_lineage_check.sql — sample UC lineage for the managed catalog.
SELECT
  source_table_full_name,
  target_table_full_name,
  event_time
FROM system.access.table_lineage
WHERE target_table_full_name LIKE '__UC_CATALOG__.%'
   OR source_table_full_name LIKE '__UC_CATALOG__.%'
ORDER BY event_time DESC
LIMIT 50;
