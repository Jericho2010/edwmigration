-- 22_fact_sale.sql
-- Silver layer: fact_sale with orphan-fact quarantine.
-- An orphan fact is a sale whose CustomerKey or StockItemKey does not resolve
-- to a current silver dimension row. Orphans go to silver.fact_sale_orphan
-- for triage; matched facts go to silver.fact_sale.

CREATE OR REPLACE TABLE edw_migration.silver.fact_sale AS
SELECT
  f.`Sale Key`                     AS sale_key,
  f.`Invoice Date Key`             AS invoice_date_key,
  f.`Customer Key`                  AS customer_key,
  f.`Stock Item Key`               AS stock_item_key,
  f.`Quantity`                     AS quantity,
  f.`Unit Price`                   AS unit_price,
  f.`Total Including Tax`          AS total_including_tax,
  f.`Profit`                       AS profit,
  f.`WWI Invoice ID`               AS wwi_invoice_id,
  f.`WWI Customer ID`              AS wwi_customer_id,
  f.`WWI Stock Item ID`            AS wwi_stock_item_id
FROM edw_migration.bronze.fact_sale f
INNER JOIN edw_migration.silver.dim_customer_scd2 c
  ON f.`Customer Key` = c.customer_sk
INNER JOIN edw_migration.silver.dim_stock_item s
  ON f.`Stock Item Key` = s.stock_item_id;

-- Orphan facts: did not match a silver dimension row
CREATE OR REPLACE TABLE edw_migration.silver.fact_sale_orphan AS
SELECT
  f.`Sale Key`                     AS sale_key,
  f.`Customer Key`                  AS customer_key,
  f.`Stock Item Key`               AS stock_item_key,
  'customer_or_stock_unmatched'    AS orphan_reason
FROM edw_migration.bronze.fact_sale f
LEFT ANTI JOIN edw_migration.silver.dim_customer_scd2 c
  ON f.`Customer Key` = c.customer_sk
LEFT ANTI JOIN edw_migration.silver.dim_stock_item s
  ON f.`Stock Item Key` = s.stock_item_id;

SELECT 'silver_fact_sale_ok' AS check_name,
       (SELECT COUNT(*) FROM edw_migration.silver.fact_sale) AS matched_rows,
       (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) AS orphan_rows;
