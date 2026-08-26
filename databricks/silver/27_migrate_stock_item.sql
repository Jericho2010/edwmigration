-- Converted from: Integration.MigrateStagedStockItemData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   silver
-- Patterns:       scd2
-- Notes:          Land-first SCD2 apply: close current dim rows whose WWI id appears in
--                 bronze.integration_stockitem_staging, then append staging versions with
--                 lineage_key. SQL Server IDENTITY Stock Item Key → max(existing)+row_number
--                 for new versions only; preserve landed keys. Lineage + ETL cutoff updated
--                 as silver side tables (no federated writes; no multi-table TRAN).

-- Open lineage key for Stock Item (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _stock_item_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Stock Item'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Per-business-key close-off timestamp from staging (MIN Valid From).
CREATE OR REPLACE TEMP VIEW _stock_item_rows_to_close AS
SELECT
  `WWI Stock Item ID` AS wwi_stock_item_id,
  MIN(`Valid From`) AS valid_from
FROM __UC_CATALOG__.bronze.integration_stockitem_staging
GROUP BY `WWI Stock Item ID`;

-- Rebuild silver dim: close-off matched current rows, keep others, append staging inserts.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.dim_stock_item AS
WITH end_of_time AS (
  SELECT CAST('9999-12-31 23:59:59.999999' AS TIMESTAMP) AS ts
),
existing_closed AS (
  SELECT
    d.`Stock Item Key` AS stock_item_key,
    d.`WWI Stock Item ID` AS stock_item_id,
    d.`Stock Item` AS stock_item_name,
    d.`Color` AS color,
    d.`Selling Package` AS selling_package,
    d.`Buying Package` AS buying_package,
    d.`Brand` AS brand,
    d.`Size` AS size,
    d.`Lead Time Days` AS lead_time_days,
    d.`Quantity Per Outer` AS quantity_per_outer,
    d.`Is Chiller Stock` AS is_chiller_stock,
    d.`Barcode` AS barcode,
    d.`Tax Rate` AS tax_rate,
    d.`Unit Price` AS unit_price,
    d.`Recommended Retail Price` AS recommended_retail_price,
    d.`Typical Weight Per Unit` AS typical_weight_per_unit,
    d.`Photo` AS photo,
    d.`Valid From` AS valid_from,
    CASE
      WHEN rtco.wwi_stock_item_id IS NOT NULL
           AND (
             d.`Valid To` = e.ts
             OR CAST(d.`Valid To` AS DATE) = DATE '9999-12-31'
           )
        THEN rtco.valid_from
      ELSE d.`Valid To`
    END AS valid_to,
    d.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.dim_stock_item d
  CROSS JOIN end_of_time e
  LEFT JOIN _stock_item_rows_to_close rtco
    ON d.`WWI Stock Item ID` = rtco.wwi_stock_item_id
),
new_versions AS (
  SELECT
    (
      SELECT COALESCE(MAX(`Stock Item Key`), 0)
      FROM __UC_CATALOG__.bronze.dim_stock_item
    ) + ROW_NUMBER() OVER (
      ORDER BY s.`WWI Stock Item ID`, s.`Valid From`
    ) AS stock_item_key,
    s.`WWI Stock Item ID` AS stock_item_id,
    s.`Stock Item` AS stock_item_name,
    s.`Color` AS color,
    s.`Selling Package` AS selling_package,
    s.`Buying Package` AS buying_package,
    s.`Brand` AS brand,
    s.`Size` AS size,
    s.`Lead Time Days` AS lead_time_days,
    s.`Quantity Per Outer` AS quantity_per_outer,
    s.`Is Chiller Stock` AS is_chiller_stock,
    s.`Barcode` AS barcode,
    s.`Tax Rate` AS tax_rate,
    s.`Unit Price` AS unit_price,
    s.`Recommended Retail Price` AS recommended_retail_price,
    s.`Typical Weight Per Unit` AS typical_weight_per_unit,
    s.`Photo` AS photo,
    s.`Valid From` AS valid_from,
    s.`Valid To` AS valid_to,
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_stockitem_staging s
  LEFT JOIN _stock_item_lineage l ON TRUE
)
SELECT * FROM existing_closed
UNION ALL
SELECT * FROM new_versions;

-- Mark Stock Item lineage row complete (silver copy; bronze land stays as-landed).
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_lineage AS
SELECT
  b.`Lineage Key` AS lineage_key,
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Lineage Key` = l.lineage_key THEN current_timestamp()
    ELSE b.`Data Load Completed`
  END AS data_load_completed,
  CASE
    WHEN b.`Lineage Key` = l.lineage_key THEN TRUE
    ELSE b.`Was Successful`
  END AS was_successful,
  b.`Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage b
LEFT JOIN _stock_item_lineage l ON TRUE;

-- Advance ETL cutoff for Stock Item from lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Stock Item' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _stock_item_lineage l ON TRUE;

SELECT 'dim_stock_item_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_stock_item) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_stock_item
        WHERE CAST(valid_to AS DATE) = DATE '9999-12-31') AS current_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.integration_lineage
        WHERE table_name = 'Stock Item' AND was_successful IS TRUE) AS lineage_ok_rows;
