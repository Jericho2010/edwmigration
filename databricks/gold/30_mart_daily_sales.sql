-- 30_mart_daily_sales.sql
-- Gold layer: mart_daily_internet_sales
-- Replaces the aggregation logic that Integration.GetStockItemUpdates +
-- downstream SSAS/SSRS reporting used to compute in the legacy EDW.
-- Pattern: CREATE OR REPLACE TABLE AS SELECT (daily grain).

CREATE OR REPLACE TABLE edw_migration.gold.mart_daily_internet_sales AS
SELECT
  d.date_key                        AS sale_date,
  s.stock_item_id,
  s.stock_item_name,
  SUM(f.quantity)                   AS quantity_sold,
  SUM(f.total_including_tax)        AS gross_revenue,
  SUM(f.profit)                     AS profit,
  COUNT(*)                          AS transaction_count
FROM edw_migration.silver.fact_sale f
INNER JOIN edw_migration.silver.dim_date d
  ON f.invoice_date_key = d.date_key
INNER JOIN edw_migration.silver.dim_stock_item s
  ON f.stock_item_key = s.stock_item_id
GROUP BY d.date_key, s.stock_item_id, s.stock_item_name;

SELECT 'gold_mart_daily_sales_ok' AS check_name,
       (SELECT COUNT(*) FROM edw_migration.gold.mart_daily_internet_sales) AS rows;
