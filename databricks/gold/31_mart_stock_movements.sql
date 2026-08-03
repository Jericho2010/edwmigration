-- 31_mart_stock_movements.sql
-- Gold: mart_stock_movements — current stockholding snapshot.
-- Join Fact.Stockholding.`Stock Item Key` to silver.dim_stock_item.stock_item_key.

CREATE OR REPLACE TABLE __UC_CATALOG__.gold.mart_stock_movements AS
SELECT
  s.stock_item_key,
  s.stock_item_id,
  s.stock_item_name,
  s.brand,
  s.size,
  s.lead_time_days,
  sh.quantity_on_hand,
  sh.quantity_allocated,
  (sh.quantity_on_hand - sh.quantity_allocated) AS quantity_available
FROM __UC_CATALOG__.silver.dim_stock_item s
LEFT JOIN (
  SELECT
    `Stock Item Key` AS stock_item_key,
    `Quantity On Hand` AS quantity_on_hand,
    `Quantity Allocated` AS quantity_allocated,
    row_number() OVER (
      PARTITION BY `Stock Item Key`
      ORDER BY `Last Edited When` DESC
    ) AS rn
  FROM __UC_CATALOG__.bronze.fact_stock_holding
) sh
  ON s.stock_item_key = sh.stock_item_key AND sh.rn = 1;

SELECT 'gold_mart_stock_movements_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.mart_stock_movements) AS rows;
