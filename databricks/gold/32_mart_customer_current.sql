-- 32_mart_customer_current.sql
-- Gold: mart_customer_current — current SCD2 customers only.

CREATE OR REPLACE TABLE __UC_CATALOG__.gold.mart_customer_current AS
SELECT
  c.customer_key,
  c.customer_id,
  c.customer_name,
  c.bill_to_customer_id,
  c.category,
  c.buying_group_id,
  c.city_id,
  ci.city_name,
  ci.state_province,
  ci.country
FROM __UC_CATALOG__.silver.dim_customer_scd2 c
LEFT JOIN __UC_CATALOG__.silver.dim_city ci
  ON c.city_id = ci.city_id
WHERE c.is_current = true;

SELECT 'gold_mart_customer_current_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.mart_customer_current) AS rows;
