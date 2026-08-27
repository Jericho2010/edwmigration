-- Converted from: Integration.MigrateStagedOrderData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   gold
-- Patterns:       scd_key_lookup, fact_replace, lineage
-- Notes:          Land-first migrate: resolve SCD2 dim keys on bronze Order_Staging via
--                 Valid From/To vs Last Modified When (COALESCE 0 unknown), drop
--                 existing bronze fact_order rows whose WWI Order ID is in staging,
--                 append resolved staging rows with new Order Key (max landed +
--                 row_number) and open Order lineage_key. Lineage + ETL cutoff updated
--                 as gold side tables. Staging key UPDATE is inlined (no federated
--                 write). Multi-table BEGIN TRAN → sequential Delta (no atomicity).

-- Open lineage key for the in-flight Order load (TOP 1 ... ORDER BY DESC).
CREATE OR REPLACE TEMP VIEW _order_lineage AS
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
staged AS (
  SELECT
    CAST(
      (
        SELECT COALESCE(MAX(`Order Key`), 0)
        FROM __UC_CATALOG__.bronze.fact_order
      ) + ROW_NUMBER() OVER (
        ORDER BY o.`Order Staging Key`
      ) AS BIGINT
    ) AS order_key,
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
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_order_staging o
  LEFT JOIN _order_city_key ck
    ON o.`Order Staging Key` = ck.order_staging_key
  LEFT JOIN _order_customer_key cu
    ON o.`Order Staging Key` = cu.order_staging_key
  LEFT JOIN _order_stock_item_key si
    ON o.`Order Staging Key` = si.order_staging_key
  LEFT JOIN _order_salesperson_key sp
    ON o.`Order Staging Key` = sp.order_staging_key
  LEFT JOIN _order_picker_key pk
    ON o.`Order Staging Key` = pk.order_staging_key
  LEFT JOIN _order_lineage l ON TRUE
)
SELECT * FROM kept
UNION ALL
SELECT * FROM staged;

-- Mark Order lineage row complete (SYSDATETIME → current_timestamp).
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
LEFT JOIN _order_lineage l ON TRUE;

-- Advance ETL cutoff for Order to the lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Order' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _order_lineage l ON TRUE;

SELECT 'fact_order_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.fact_order) AS order_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.integration_lineage
        WHERE table_name = 'Order' AND was_successful IS TRUE) AS order_lineage_ok;
