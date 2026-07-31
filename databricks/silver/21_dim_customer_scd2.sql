-- 21_dim_customer_scd2.sql
-- Silver layer: SCD2 customer dimension.
-- WWI Dimension.Customer has Valid From / Valid To columns that already model
-- history. We surface them as a proper SCD2 with is_current and a surrogate
-- key, and we quarantine rows whose Valid To is null but Valid From is in the
-- future (data-quality check).

CREATE OR REPLACE TABLE edw_migration.silver.dim_customer_scd2 AS
SELECT
  `WWI Customer ID`                AS customer_id,
  `Customer`                       AS customer_name,
  `Bill To Customer`               AS bill_to_customer_id,
  `Category`                       AS category,
  `Buying Group`                   AS buying_group_id,
  `City`                           AS city_id,
  `Valid From`                     AS valid_from,
  `Valid To`                       AS valid_to,
  CASE WHEN `Valid To` IS NULL OR `Valid To` = '9999-12-31' THEN true ELSE false END AS is_current,
  -- Surrogate key: monotonically increasing, stable across re-runs
  monotonically_increasing_id()    AS customer_sk
FROM edw_migration.bronze.dim_customer
WHERE `Valid From` <= current_timestamp();  -- quarantine future-dated rows

-- Data-quality: count quarantined rows (future-dated Valid From)
CREATE OR REPLACE VIEW edw_migration.silver.dim_customer_scd2_quarantine AS
SELECT *
FROM edw_migration.bronze.dim_customer
WHERE `Valid From` > current_timestamp();

SELECT 'silver_dim_customer_scd2_ok' AS check_name,
       (SELECT COUNT(*) FROM edw_migration.silver.dim_customer_scd2) AS scd2_rows,
       (SELECT COUNT(*) FROM edw_migration.silver.dim_customer_scd2 WHERE is_current) AS current_rows,
       (SELECT COUNT(*) FROM edw_migration.silver.dim_customer_scd2_quarantine) AS quarantined_rows;
