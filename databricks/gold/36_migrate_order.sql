-- Converted from: Integration.MigrateStagedOrderData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   gold
-- Patterns:       scd_key_lookup, fact_replace, lineage
-- Notes:          Land-first migrate: resolve SCD2 dim keys on bronze staging via
--                 Valid From/To vs Last Modified When (COALESCE 0 unknown), drop
--                 existing gold/bronze fact_order rows whose WWI Order ID is in
--                 staging, append resolved staging rows with open Order lineage_key.
--                 Lineage + ETL cutoff updated as gold side tables. Multi-table
--                 BEGIN TRAN → sequential Delta statements (no cross-table atomicity).
--                 Order Key IDENTITY → preserve kept keys; max+row_number for inserts.

-- Open lineage key for the in-flight Order load (TOP 1 ... ORDER BY DESC).
CREATE OR REPLACE TEMP VIEW _order_lineage_key AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Order'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Resolve City Key (SCD2 as-of Last Modified When; TOP 1 ORDER BY Valid From).
CREATE OR REPLACE TEMP VIEW _order_city_key AS
SELECT order_staging_key, city_key
FROM (
  SELECT
    o.`Order Staging Key` AS order_staging_key,
    c.`City Key` AS city_key,
    ROW_NUMBER() OVER (
      PARTITION BY o.`Order Staging Key`
      ORDER BY c.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_order_staging o
  INNER JOIN __UC_CATALOG__.bronze.dim_city c
    ON c.`WWI City ID` = o.`WWI City ID`
   AND o.`Last Modified When` > c.`Valid From`
   AND o.`Last Modified When` <= c.`Valid To`
) x
WHERE rn = 1;

-- Resolve Customer Key.
CREATE OR REPLACE TEMP VIEW _order_customer_key AS
SELECT order_staging_key, customer_key
FROM (
  SELECT
    o.`Order Staging Key` AS order_staging_key,
    c.`Customer Key` AS customer_key,
    ROW_NUMBER() OVER (
      PARTITION BY o.`Order Staging Key`
      ORDER BY c.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_order_staging o
  INNER JOIN __UC_CATALOG__.bronze.dim_customer c
    ON c.`WWI Customer ID` = o.`WWI Customer ID`
   AND o.`Last Modified When` > c.`Valid From`
   AND o.`Last Modified When` <= c.`Valid To`
) x
WHERE rn = 1;

-- Resolve Stock Item Key.
CREATE OR REPLACE TEMP VIEW _order_stock_item_key AS
SELECT order_staging_key, stock_item_key
FROM (
  SELECT
    o.`Order Staging Key` AS order_staging_key,
    si.`Stock Item Key` AS stock_item_key,
    ROW_NUMBER() OVER (
      PARTITION BY o.`Order Staging Key`
      ORDER BY si.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_order_staging o
  INNER JOIN __UC_CATALOG__.bronze.dim_stock_item si
    ON si.`WWI Stock Item ID` = o.`WWI Stock Item ID`
   AND o.`Last Modified When` > si.`Valid From`
   AND o.`Last Modified When` <= si.`Valid To`
) x
WHERE rn = 1;

-- Resolve Salesperson Key (Employee keyed by WWI Salesperson ID).
CREATE OR REPLACE TEMP VIEW _order_salesperson_key AS
SELECT order_staging_key, salesperson_key
FROM (
  SELECT
    o.`Order Staging Key` AS order_staging_key,
    e.`Employee Key` AS salesperson_key,
    ROW_NUMBER() OVER (
      PARTITION BY o.`Order Staging Key`
      ORDER BY e.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_order_staging o
  INNER JOIN __UC_CATALOG__.bronze.dim_employee e
    ON e.`WWI Employee ID` = o.`WWI Salesperson ID`
   AND o.`Last Modified When` > e.`Valid From`
   AND o.`Last Modified When` <= e.`Valid To`
) x
WHERE rn = 1;

-- Resolve Picker Key (Employee keyed by WWI Picker ID).
CREATE OR REPLACE TEMP VIEW _order_picker_key AS
SELECT order_staging_key, picker_key
FROM (
  SELECT
    o.`Order Staging Key` AS order_staging_key,
    e.`Employee Key` AS picker_key,
    ROW_NUMBER() OVER (
      PARTITION BY o.`Order Staging Key`
      ORDER BY e.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_order_staging o
  INNER JOIN __UC_CATALOG__.bronze.dim_employee e
    ON e.`WWI Employee ID` = o.`WWI Picker ID`
   AND o.`Last Modified When` > e.`Valid From`
   AND o.`Last Modified When` <= e.`Valid To`
) x
WHERE rn = 1;

-- Staging rows with resolved dim keys + lineage (unknown key → 0).
CREATE OR REPLACE TEMP VIEW _order_staging_resolved AS
SELECT
  COALESCE(ck.city_key, 0) AS city_key,
  COALESCE(cu.customer_key, 0) AS customer_key,
  COALESCE(si.stock_item_key, 0) AS stock_item_key,
  o.`Order Date Key` AS order_date_key,
  o.`Picked Date Key` AS picked_date_key,
  COALESCE(sp.salesperson_key, 0) AS salesperson_key,
  COALESCE(pk.picker_key, 0) AS picker_key,
  o.`WWI Order ID` AS wwi_order_id,
  o.`WWI Backorder ID` AS wwi_backorder_id,
  o.`Description` AS description,
  o.`Package` AS package,
  o.`Quantity` AS quantity,
  o.`Unit Price` AS unit_price,
  o.`Tax Rate` AS tax_rate,
  o.`Total Excluding Tax` AS total_excluding_tax,
  o.`Tax Amount` AS tax_amount,
  o.`Total Including Tax` AS total_including_tax,
  lk.lineage_key
FROM __UC_CATALOG__.bronze.integration_order_staging o
CROSS JOIN _order_lineage_key lk
LEFT JOIN _order_city_key ck
  ON o.`Order Staging Key` = ck.order_staging_key
LEFT JOIN _order_customer_key cu
  ON o.`Order Staging Key` = cu.order_staging_key
LEFT JOIN _order_stock_item_key si
  ON o.`Order Staging Key` = si.order_staging_key
LEFT JOIN _order_salesperson_key sp
  ON o.`Order Staging Key` = sp.order_staging_key
LEFT JOIN _order_picker_key pk
  ON o.`Order Staging Key` = pk.order_staging_key;

-- Rebuild fact_order: keep rows not in staging WWI Order IDs; append resolved staging.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.fact_order AS
WITH kept AS (
  SELECT
    f.`Order Key` AS order_key,
    f.`City Key` AS city_key,
    f.`Customer Key` AS customer_key,
    f.`Stock Item Key` AS stock_item_key,
    f.`Order Date Key` AS order_date_key,
    f.`Picked Date Key` AS picked_date_key,
    f.`Salesperson Key` AS salesperson_key,
    f.`Picker Key` AS picker_key,
    f.`WWI Order ID` AS wwi_order_id,
    f.`WWI Backorder ID` AS wwi_backorder_id,
    f.`Description` AS description,
    f.`Package` AS package,
    f.`Quantity` AS quantity,
    f.`Unit Price` AS unit_price,
    f.`Tax Rate` AS tax_rate,
    f.`Total Excluding Tax` AS total_excluding_tax,
    f.`Tax Amount` AS tax_amount,
    f.`Total Including Tax` AS total_including_tax,
    f.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.fact_order f
  WHERE NOT EXISTS (
    SELECT 1
    FROM __UC_CATALOG__.bronze.integration_order_staging s
    WHERE s.`WWI Order ID` = f.`WWI Order ID`
  )
),
max_key AS (
  SELECT COALESCE(MAX(order_key), 0) AS max_order_key
  FROM kept
),
staged AS (
  SELECT
    CAST(mk.max_order_key + ROW_NUMBER() OVER (
      ORDER BY r.wwi_order_id, r.stock_item_key, r.description
    ) AS BIGINT) AS order_key,
    r.city_key,
    r.customer_key,
    r.stock_item_key,
    r.order_date_key,
    r.picked_date_key,
    r.salesperson_key,
    r.picker_key,
    r.wwi_order_id,
    r.wwi_backorder_id,
    r.description,
    r.package,
    r.quantity,
    r.unit_price,
    r.tax_rate,
    r.total_excluding_tax,
    r.tax_amount,
    r.total_including_tax,
    r.lineage_key
  FROM _order_staging_resolved r
  CROSS JOIN max_key mk
)
SELECT * FROM kept
UNION ALL
SELECT * FROM staged;

-- Mark Order lineage row complete (SYSDATETIME → current_timestamp).
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.integration_lineage AS
SELECT
  l.`Lineage Key` AS lineage_key,
  l.`Table Name` AS table_name,
  l.`Source System Cutoff Time` AS source_system_cutoff_time,
  CASE
    WHEN l.`Lineage Key` = (SELECT lineage_key FROM _order_lineage_key)
         AND l.`Table Name` = 'Order'
         AND l.`Data Load Completed` IS NULL
      THEN current_timestamp()
    ELSE l.`Data Load Completed`
  END AS data_load_completed,
  CASE
    WHEN l.`Lineage Key` = (SELECT lineage_key FROM _order_lineage_key)
         AND l.`Table Name` = 'Order'
         AND l.`Data Load Completed` IS NULL
      THEN true
    ELSE CAST(l.`Was Successful` AS BOOLEAN)
  END AS was_successful
FROM __UC_CATALOG__.bronze.integration_lineage l;

-- Advance ETL cutoff for Order to the lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.integration_etl_cutoff AS
SELECT
  c.`Table Name` AS table_name,
  CASE
    WHEN c.`Table Name` = 'Order'
      THEN COALESCE(
        (SELECT source_system_cutoff_time FROM _order_lineage_key),
        c.`Cutoff Time`
      )
    ELSE c.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff c;

SELECT 'fact_order_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.fact_order) AS order_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.integration_lineage
        WHERE table_name = 'Order' AND was_successful = true) AS order_lineage_ok;
