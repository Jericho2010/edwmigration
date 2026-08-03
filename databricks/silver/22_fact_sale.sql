-- 22_fact_sale.sql
-- Silver layer: fact_sale with orphan-fact quarantine.
-- Join Fact.Sale DW surrogates to silver dimension keys:
--   Customer Key  -> silver.dim_customer_scd2.customer_key
--   Stock Item Key -> silver.dim_stock_item.stock_item_key

CREATE OR REPLACE TABLE __UC_CATALOG__.silver.fact_sale AS
SELECT
  f.`Sale Key` AS sale_key,
  f.`Invoice Date Key` AS invoice_date_key,
  f.`Customer Key` AS customer_key,
  f.`Stock Item Key` AS stock_item_key,
  f.`Quantity` AS quantity,
  f.`Unit Price` AS unit_price,
  f.`Total Including Tax` AS total_including_tax,
  f.`Profit` AS profit,
  f.`WWI Invoice ID` AS wwi_invoice_id,
  f.`WWI Customer ID` AS wwi_customer_id,
  f.`WWI Stock Item ID` AS wwi_stock_item_id
FROM __UC_CATALOG__.bronze.fact_sale f
INNER JOIN __UC_CATALOG__.silver.dim_customer_scd2 c
  ON f.`Customer Key` = c.customer_key
INNER JOIN __UC_CATALOG__.silver.dim_stock_item s
  ON f.`Stock Item Key` = s.stock_item_key;

CREATE OR REPLACE TABLE __UC_CATALOG__.silver.fact_sale_orphan AS
SELECT
  f.`Sale Key` AS sale_key,
  f.`Customer Key` AS customer_key,
  f.`Stock Item Key` AS stock_item_key,
  CASE
    WHEN c.customer_key IS NULL AND s.stock_item_key IS NULL THEN 'customer_and_stock_unmatched'
    WHEN c.customer_key IS NULL THEN 'customer_unmatched'
    ELSE 'stock_unmatched'
  END AS orphan_reason
FROM __UC_CATALOG__.bronze.fact_sale f
LEFT JOIN __UC_CATALOG__.silver.dim_customer_scd2 c
  ON f.`Customer Key` = c.customer_key
LEFT JOIN __UC_CATALOG__.silver.dim_stock_item s
  ON f.`Stock Item Key` = s.stock_item_key
WHERE c.customer_key IS NULL OR s.stock_item_key IS NULL;

SELECT 'silver_fact_sale_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.fact_sale) AS matched_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.fact_sale_orphan) AS orphan_rows;
