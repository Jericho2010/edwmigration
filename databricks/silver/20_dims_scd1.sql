-- 20_dims_scd1.sql
-- Silver layer: SCD1 dimensions (City, StockItem, Date).
-- Conform types, normalize keys, drop audit columns. SCD1 = latest-wins.

-- ---------------------------------------------------------------------------
-- silver.dim_city (SCD1)
-- Source: bronze.dim_city (WWI Dimension.City)
-- WWI column names contain spaces; we select them via backticks and alias
-- to snake_case for the silver/gold layers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE edw_migration.silver.dim_city AS
SELECT
  `WWI City ID`                   AS city_id,
  `City`                           AS city_name,
  `State Province`                 AS state_province,
  `Country`                        AS country,
  `Latest Recorded Population`     AS latest_population,
  `Valid From`                     AS valid_from,
  `Valid To`                       AS valid_to
FROM edw_migration.bronze.dim_city;

-- ---------------------------------------------------------------------------
-- silver.dim_stock_item (SCD1)
-- Source: bronze.dim_stock_item (WWI Dimension.Stock Item)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE edw_migration.silver.dim_stock_item AS
SELECT
  `WWI Stock Item ID`              AS stock_item_id,
  `Stock Item`                     AS stock_item_name,
  `Brand`                          AS brand,
  `Size`                           AS size,
  `Lead Time Days`                 AS lead_time_days,
  `Valid From`                     AS valid_from,
  `Valid To`                       AS valid_to
FROM edw_migration.bronze.dim_stock_item;

-- ---------------------------------------------------------------------------
-- silver.dim_date (SCD1)
-- Source: bronze.dim_date (WWI Dimension.Date)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE edw_migration.silver.dim_date AS
SELECT
  `Date`                           AS date_key,
  `Day Number`                     AS day_number,
  `Day`                            AS day_name,
  `Month`                          AS month_name,
  `Calendar Year`                   AS calendar_year,
  `Calendar Month Number`          AS calendar_month_number,
  `Calendar Quarter`               AS calendar_quarter
FROM edw_migration.bronze.dim_date;

SELECT 'silver_dims_scd1_ok' AS check_name,
       (SELECT COUNT(*) FROM edw_migration.silver.dim_city) AS dim_city_rows,
       (SELECT COUNT(*) FROM edw_migration.silver.dim_stock_item) AS dim_stock_item_rows,
       (SELECT COUNT(*) FROM edw_migration.silver.dim_date) AS dim_date_rows;
