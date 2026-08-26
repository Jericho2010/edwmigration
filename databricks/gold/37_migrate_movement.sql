-- Converted from: Integration.MigrateStagedMovementData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   gold
-- Patterns:       merge, dimension_key_lookup
-- Notes:          Land-first fact merge: resolve SCD2 dimension keys from bronze dims
--                 against Movement_Staging (`Last Modifed When` typo preserved from WWI),
--                 MERGE semantics via rebuild of gold.fact_movement on
--                 WWI Stock Item Transaction ID, then mark lineage complete and advance
--                 ETL cutoff as gold side tables (no federated writes; no multi-table TRAN).

-- Open lineage key for Movement (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _movement_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Movement'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Staging + SCD2 dim key resolution (set-based stand-in for correlated TOP 1 updates).
CREATE OR REPLACE TEMP VIEW _movement_staged AS
WITH base AS (
  SELECT
    m.`Date Key` AS date_key,
    m.`WWI Stock Item Transaction ID` AS wwi_stock_item_transaction_id,
    m.`WWI Invoice ID` AS wwi_invoice_id,
    m.`WWI Purchase Order ID` AS wwi_purchase_order_id,
    m.Quantity AS quantity,
    m.`WWI Stock Item ID` AS wwi_stock_item_id,
    m.`WWI Customer ID` AS wwi_customer_id,
    m.`WWI Supplier ID` AS wwi_supplier_id,
    m.`WWI Transaction Type ID` AS wwi_transaction_type_id,
    m.`Last Modifed When` AS last_modifed_when
  FROM __UC_CATALOG__.bronze.integration_movement_staging m
),
stock_item_keys AS (
  SELECT
    b.wwi_stock_item_transaction_id,
    si.`Stock Item Key` AS stock_item_key,
    ROW_NUMBER() OVER (
      PARTITION BY b.wwi_stock_item_transaction_id
      ORDER BY si.`Valid From`
    ) AS rn
  FROM base b
  INNER JOIN __UC_CATALOG__.bronze.dim_stock_item si
    ON si.`WWI Stock Item ID` = b.wwi_stock_item_id
   AND b.last_modifed_when > si.`Valid From`
   AND b.last_modifed_when <= si.`Valid To`
),
customer_keys AS (
  SELECT
    b.wwi_stock_item_transaction_id,
    c.`Customer Key` AS customer_key,
    ROW_NUMBER() OVER (
      PARTITION BY b.wwi_stock_item_transaction_id
      ORDER BY c.`Valid From`
    ) AS rn
  FROM base b
  INNER JOIN __UC_CATALOG__.bronze.dim_customer c
    ON c.`WWI Customer ID` = b.wwi_customer_id
   AND b.last_modifed_when > c.`Valid From`
   AND b.last_modifed_when <= c.`Valid To`
),
supplier_keys AS (
  SELECT
    b.wwi_stock_item_transaction_id,
    s.`Supplier Key` AS supplier_key,
    ROW_NUMBER() OVER (
      PARTITION BY b.wwi_stock_item_transaction_id
      ORDER BY s.`Valid From`
    ) AS rn
  FROM base b
  INNER JOIN __UC_CATALOG__.bronze.dim_supplier s
    ON s.`WWI Supplier ID` = b.wwi_supplier_id
   AND b.last_modifed_when > s.`Valid From`
   AND b.last_modifed_when <= s.`Valid To`
),
transaction_type_keys AS (
  SELECT
    b.wwi_stock_item_transaction_id,
    tt.`Transaction Type Key` AS transaction_type_key,
    ROW_NUMBER() OVER (
      PARTITION BY b.wwi_stock_item_transaction_id
      ORDER BY tt.`Valid From`
    ) AS rn
  FROM base b
  INNER JOIN __UC_CATALOG__.bronze.dim_transaction_type tt
    ON tt.`WWI Transaction Type ID` = b.wwi_transaction_type_id
   AND b.last_modifed_when > tt.`Valid From`
   AND b.last_modifed_when <= tt.`Valid To`
)
SELECT
  b.date_key,
  COALESCE(sik.stock_item_key, 0) AS stock_item_key,
  COALESCE(ck.customer_key, 0) AS customer_key,
  COALESCE(suk.supplier_key, 0) AS supplier_key,
  COALESCE(ttk.transaction_type_key, 0) AS transaction_type_key,
  b.wwi_stock_item_transaction_id,
  b.wwi_invoice_id,
  b.wwi_purchase_order_id,
  b.quantity,
  l.lineage_key
FROM base b
LEFT JOIN _movement_lineage l ON TRUE
LEFT JOIN stock_item_keys sik
  ON b.wwi_stock_item_transaction_id = sik.wwi_stock_item_transaction_id
 AND sik.rn = 1
LEFT JOIN customer_keys ck
  ON b.wwi_stock_item_transaction_id = ck.wwi_stock_item_transaction_id
 AND ck.rn = 1
LEFT JOIN supplier_keys suk
  ON b.wwi_stock_item_transaction_id = suk.wwi_stock_item_transaction_id
 AND suk.rn = 1
LEFT JOIN transaction_type_keys ttk
  ON b.wwi_stock_item_transaction_id = ttk.wwi_stock_item_transaction_id
 AND ttk.rn = 1;

-- MERGE Fact.Movement: keep rows not in staging; upsert staging rows (matched update / not-matched insert).
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.fact_movement AS
SELECT
  f.`Date Key` AS date_key,
  f.`Stock Item Key` AS stock_item_key,
  f.`Customer Key` AS customer_key,
  f.`Supplier Key` AS supplier_key,
  f.`Transaction Type Key` AS transaction_type_key,
  f.`WWI Stock Item Transaction ID` AS wwi_stock_item_transaction_id,
  f.`WWI Invoice ID` AS wwi_invoice_id,
  f.`WWI Purchase Order ID` AS wwi_purchase_order_id,
  f.Quantity AS quantity,
  f.`Lineage Key` AS lineage_key
FROM __UC_CATALOG__.bronze.fact_movement f
WHERE NOT EXISTS (
  SELECT 1
  FROM _movement_staged s
  WHERE s.wwi_stock_item_transaction_id = f.`WWI Stock Item Transaction ID`
)
UNION ALL
SELECT
  date_key,
  stock_item_key,
  customer_key,
  supplier_key,
  transaction_type_key,
  wwi_stock_item_transaction_id,
  wwi_invoice_id,
  wwi_purchase_order_id,
  quantity,
  lineage_key
FROM _movement_staged;

-- Mark Movement lineage row complete (gold copy; bronze land stays as-landed).
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
LEFT JOIN _movement_lineage l ON TRUE;

-- Advance ETL cutoff for Movement from lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Movement' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _movement_lineage l ON TRUE;

SELECT 'fact_movement_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.fact_movement) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.integration_lineage
        WHERE table_name = 'Movement' AND was_successful IS TRUE) AS lineage_ok_rows;
