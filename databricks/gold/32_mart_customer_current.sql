-- 32_mart_customer_current.sql
-- Gold layer: mart_customer_current
-- Replaces Integration.MigrateStagedCustomerData (mutating proc).
-- Pattern: current-state snapshot (only is_current = true rows).

CREATE OR REPLACE TABLE edw_migration.gold.mart_customer_current AS
SELECT
  c.customer_id,
  c.customer_name,
  c.bill_to_customer_id,
  c.category,
  c.buying_group_id,
  c.city_id,
  ci.city_name,
  ci.state_province,
  ci.country
FROM edw_migration.silver.dim_customer_scd2 c
LEFT JOIN edw_migration.silver.dim_city ci
  ON c.city_id = ci.city_id
WHERE c.is_current = true;

SELECT 'gold_mart_customer_current_ok' AS check_name,
       (SELECT COUNT(*) FROM edw_migration.gold.mart_customer_current) AS rows;
