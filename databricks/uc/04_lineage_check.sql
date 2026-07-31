-- 04_lineage_check.sql (optional showcase)
-- Unity Catalog automatically tracks lineage for medallion tables.
-- Run after a successful medallion job to demonstrate system.access.table_lineage.
--
-- Requires system schema access (Free Edition workspaces usually have this for
-- the workspace admin).

SELECT
  source_table_full_name,
  target_table_full_name,
  event_time
FROM system.access.table_lineage
WHERE target_table_full_name LIKE 'edw_migration.%'
   OR source_table_full_name LIKE 'edw_migration.%'
ORDER BY event_time DESC
LIMIT 50;
