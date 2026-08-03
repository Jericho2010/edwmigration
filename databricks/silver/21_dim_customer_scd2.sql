-- 21_dim_customer_scd2.sql
-- Silver layer: SCD2 customer dimension.
-- Preserve WWI `Customer Key` as the DW surrogate used by Fact.Sale.
-- Do NOT invent a join key with monotonically_increasing_id().

CREATE OR REPLACE TABLE __UC_CATALOG__.silver.dim_customer_scd2 AS
SELECT
  `Customer Key` AS customer_key,
  `WWI Customer ID` AS customer_id,
  `Customer` AS customer_name,
  `Bill To Customer` AS bill_to_customer_id,
  `Category` AS category,
  `Buying Group` AS buying_group_id,
  `City` AS city_id,
  `Valid From` AS valid_from,
  `Valid To` AS valid_to,
  CASE
    WHEN `Valid To` IS NULL OR CAST(`Valid To` AS DATE) = DATE '9999-12-31' THEN true
    ELSE false
  END AS is_current
FROM __UC_CATALOG__.bronze.dim_customer
WHERE `Valid From` <= current_timestamp();

CREATE OR REPLACE VIEW __UC_CATALOG__.silver.dim_customer_scd2_quarantine AS
SELECT *
FROM __UC_CATALOG__.bronze.dim_customer
WHERE `Valid From` > current_timestamp();

SELECT 'silver_dim_customer_scd2_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_customer_scd2) AS scd2_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_customer_scd2 WHERE is_current) AS current_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_customer_scd2_quarantine) AS quarantined_rows;
