-- Converted from: Integration.MigrateStagedPurchaseData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   gold
-- Patterns:       scd_key_lookup, delete_insert_rebuild
-- Notes:          Land-first fact migrate: resolve Supplier/Stock Item keys via SCD
--                 point-in-time lookup on bronze dims, drop existing Fact.Purchase rows
--                 whose WWI Purchase Order ID appears in staging, then append staged
--                 lines with open Purchase lineage_key. Lineage + ETL cutoff updated as
--                 gold side tables (no federated writes; no multi-table TRAN).

-- Open lineage key for Purchase (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _purchase_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Purchase'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Staging rows with SCD key lookups (COALESCE to 0 when no matching dim version).
CREATE OR REPLACE TEMP VIEW _purchase_staged_keyed AS
WITH supplier_ranked AS (
  SELECT
    p.`Date Key` AS date_key,
    p.`WWI Supplier ID` AS wwi_supplier_id,
    p.`WWI Stock Item ID` AS wwi_stock_item_id,
    p.`WWI Purchase Order ID` AS wwi_purchase_order_id,
    p.`Ordered Outers` AS ordered_outers,
    p.`Ordered Quantity` AS ordered_quantity,
    p.`Received Outers` AS received_outers,
    p.`Package` AS package,
    p.`Is Order Finalized` AS is_order_finalized,
    p.`Last Modified When` AS last_modified_when,
    s.`Supplier Key` AS supplier_key,
    ROW_NUMBER() OVER (
      PARTITION BY
        p.`Date Key`,
        p.`WWI Supplier ID`,
        p.`WWI Stock Item ID`,
        p.`WWI Purchase Order ID`,
        p.`Ordered Outers`,
        p.`Ordered Quantity`,
        p.`Received Outers`,
        p.`Package`,
        p.`Is Order Finalized`,
        p.`Last Modified When`
      ORDER BY s.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_purchase_staging p
  LEFT JOIN __UC_CATALOG__.bronze.dim_supplier s
    ON s.`WWI Supplier ID` = p.`WWI Supplier ID`
   AND p.`Last Modified When` > s.`Valid From`
   AND p.`Last Modified When` <= s.`Valid To`
),
supplier_picked AS (
  SELECT
    date_key,
    wwi_supplier_id,
    wwi_stock_item_id,
    wwi_purchase_order_id,
    ordered_outers,
    ordered_quantity,
    received_outers,
    package,
    is_order_finalized,
    last_modified_when,
    COALESCE(supplier_key, 0) AS supplier_key
  FROM supplier_ranked
  WHERE rn = 1
),
stock_ranked AS (
  SELECT
    sp.*,
    si.`Stock Item Key` AS stock_item_key,
    ROW_NUMBER() OVER (
      PARTITION BY
        sp.date_key,
        sp.wwi_supplier_id,
        sp.wwi_stock_item_id,
        sp.wwi_purchase_order_id,
        sp.ordered_outers,
        sp.ordered_quantity,
        sp.received_outers,
        sp.package,
        sp.is_order_finalized,
        sp.last_modified_when
      ORDER BY si.`Valid From`
    ) AS rn
  FROM supplier_picked sp
  LEFT JOIN __UC_CATALOG__.bronze.dim_stock_item si
    ON si.`WWI Stock Item ID` = sp.wwi_stock_item_id
   AND sp.last_modified_when > si.`Valid From`
   AND sp.last_modified_when <= si.`Valid To`
)
SELECT
  sr.date_key,
  sr.supplier_key,
  COALESCE(sr.stock_item_key, 0) AS stock_item_key,
  sr.wwi_purchase_order_id,
  sr.ordered_outers,
  sr.ordered_quantity,
  sr.received_outers,
  sr.package,
  sr.is_order_finalized,
  l.lineage_key
FROM stock_ranked sr
LEFT JOIN _purchase_lineage l ON TRUE
WHERE sr.rn = 1;

-- Rebuild gold fact: keep rows whose PO id is not in staging; append keyed staging.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.fact_purchase AS
WITH staged_po AS (
  SELECT DISTINCT wwi_purchase_order_id
  FROM _purchase_staged_keyed
),
kept AS (
  SELECT
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
  LEFT JOIN staged_po sp
    ON f.`WWI Purchase Order ID` = sp.wwi_purchase_order_id
  WHERE sp.wwi_purchase_order_id IS NULL
)
SELECT * FROM kept
UNION ALL
SELECT
  date_key,
  supplier_key,
  stock_item_key,
  wwi_purchase_order_id,
  ordered_outers,
  ordered_quantity,
  received_outers,
  package,
  is_order_finalized,
  lineage_key
FROM _purchase_staged_keyed;

-- Mark Purchase lineage row complete (gold copy; bronze land stays as-landed).
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
    ELSE b.`Was Successful`
  END AS was_successful,
  b.`Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage b
LEFT JOIN _purchase_lineage l ON TRUE;

-- Advance ETL cutoff for Purchase from lineage source-system cutoff.
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
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.fact_purchase) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.integration_lineage
        WHERE table_name = 'Purchase' AND was_successful IS TRUE) AS lineage_ok_rows;
