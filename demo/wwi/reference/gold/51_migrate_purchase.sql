-- Converted from: Integration.MigrateStagedPurchaseData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   gold
-- Patterns:       scd_key_lookup, fact_replace, lineage
-- Notes:          Land-first migrate: resolve Supplier/Stock Item SCD2 keys on
--                 bronze Purchase_Staging (Valid From/To vs Last Modified When;
--                 COALESCE 0 unknown). Drop bronze fact_purchase rows whose
--                 WWI Purchase Order ID is in staging, append resolved staging
--                 with new Purchase Key (max landed + row_number) and open
--                 Purchase lineage_key. Staging key UPDATE is inlined (no
--                 federated write). Lineage + ETL cutoff as gold side tables.
--                 Multi-table BEGIN TRAN → sequential Delta (no atomicity).

-- Open lineage key for the in-flight Purchase load (TOP 1 ... ORDER BY DESC).
CREATE OR REPLACE TEMP VIEW _purchase_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Purchase'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Resolve Supplier Key (SCD2 as-of Last Modified When; TOP 1 ORDER BY Valid From).
CREATE OR REPLACE TEMP VIEW _purchase_supplier_key AS
SELECT purchase_staging_key, supplier_key
FROM (
  SELECT
    p.`Purchase Staging Key` AS purchase_staging_key,
    s.`Supplier Key` AS supplier_key,
    ROW_NUMBER() OVER (
      PARTITION BY p.`Purchase Staging Key`
      ORDER BY s.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_purchase_staging p
  INNER JOIN __UC_CATALOG__.bronze.dim_supplier s
    ON s.`WWI Supplier ID` = p.`WWI Supplier ID`
   AND p.`Last Modified When` > s.`Valid From`
   AND p.`Last Modified When` <= s.`Valid To`
) x
WHERE rn = 1;

-- Resolve Stock Item Key (SCD2 as-of Last Modified When; TOP 1 ORDER BY Valid From).
CREATE OR REPLACE TEMP VIEW _purchase_stock_item_key AS
SELECT purchase_staging_key, stock_item_key
FROM (
  SELECT
    p.`Purchase Staging Key` AS purchase_staging_key,
    si.`Stock Item Key` AS stock_item_key,
    ROW_NUMBER() OVER (
      PARTITION BY p.`Purchase Staging Key`
      ORDER BY si.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_purchase_staging p
  INNER JOIN __UC_CATALOG__.bronze.dim_stock_item si
    ON si.`WWI Stock Item ID` = p.`WWI Stock Item ID`
   AND p.`Last Modified When` > si.`Valid From`
   AND p.`Last Modified When` <= si.`Valid To`
) x
WHERE rn = 1;

-- Rebuild fact_purchase: keep rows not in staging WWI Purchase Order IDs; append resolved staging.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.fact_purchase AS
WITH kept AS (
  SELECT
    f.`Purchase Key` AS purchase_key,
    f.`Date Key` AS date_key,
    f.`Supplier Key` AS supplier_key,
    f.`Stock Item Key` AS stock_item_key,
    f.`WWI Purchase Order ID` AS wwi_purchase_order_id,
    f.`Ordered Outers` AS ordered_outers,
    f.`Ordered Quantity` AS ordered_quantity,
    f.`Received Outers` AS received_outers,
    f.`Package` AS package,
    f.`Is Order Finalized` AS is_order_finalized,
    f.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.fact_purchase f
  WHERE NOT EXISTS (
    SELECT 1
    FROM __UC_CATALOG__.bronze.integration_purchase_staging s
    WHERE s.`WWI Purchase Order ID` = f.`WWI Purchase Order ID`
  )
),
staged AS (
  SELECT
    CAST(
      (
        SELECT COALESCE(MAX(`Purchase Key`), 0)
        FROM __UC_CATALOG__.bronze.fact_purchase
      ) + ROW_NUMBER() OVER (
        ORDER BY p.`Purchase Staging Key`
      ) AS BIGINT
    ) AS purchase_key,
    p.`Date Key` AS date_key,
    COALESCE(sk.supplier_key, 0) AS supplier_key,
    COALESCE(si.stock_item_key, 0) AS stock_item_key,
    p.`WWI Purchase Order ID` AS wwi_purchase_order_id,
    p.`Ordered Outers` AS ordered_outers,
    p.`Ordered Quantity` AS ordered_quantity,
    p.`Received Outers` AS received_outers,
    p.`Package` AS package,
    p.`Is Order Finalized` AS is_order_finalized,
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_purchase_staging p
  LEFT JOIN _purchase_supplier_key sk
    ON p.`Purchase Staging Key` = sk.purchase_staging_key
  LEFT JOIN _purchase_stock_item_key si
    ON p.`Purchase Staging Key` = si.purchase_staging_key
  LEFT JOIN _purchase_lineage l ON TRUE
)
SELECT * FROM kept
UNION ALL
SELECT * FROM staged;

-- Mark Purchase lineage row complete (SYSDATETIME → current_timestamp).
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.integration_lineage AS
SELECT
  b.`Lineage Key` AS lineage_key,
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Lineage Key` = l.lineage_key THEN current_timestamp()
    ELSE b.`Data Load Completed`
  END AS data_load_completed,
  CASE
    WHEN b.`Lineage Key` = l.lineage_key THEN TRUE
    ELSE CAST(b.`Was Successful` AS BOOLEAN)
  END AS was_successful,
  b.`Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage b
LEFT JOIN _purchase_lineage l ON TRUE;

-- Advance ETL cutoff for Purchase to the lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Purchase' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _purchase_lineage l ON TRUE;

SELECT 'fact_purchase_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.fact_purchase) AS purchase_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.integration_lineage
        WHERE table_name = 'Purchase' AND was_successful IS TRUE) AS purchase_lineage_ok;
