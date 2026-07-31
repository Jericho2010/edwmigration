-- 31_mart_stock_movements.sql
-- Gold layer: mart_stock_movements
-- Replaces Integration.MigrateStagedStockItemData (a mutating proc whose
-- fixture is the target Dimension table state after execution).
-- Pattern: INSERT OVERWRITE snapshot (current-state grain).

CREATE OR REPLACE TABLE edw_migration.gold.mart_stock_movements AS
SELECT
  s.stock_item_id,
  s.stock_item_name,
  s.brand,
  s.size,
  s.lead_time_days,
  -- Latest stockholding per item (WWI Fact.Stockholding)
  sh.quantity_on_hand,
  sh.quantity_allocated,
  (sh.quantity_on_hand - sh.quantity_allocated) AS quantity_available
FROM edw_migration.silver.dim_stock_item s
LEFT JOIN (
  SELECT
    `Stock Item Key`               AS stock_item_key,
    `Quantity On Hand`              AS quantity_on_hand,
    `Quantity Allocated`            AS quantity_allocated,
    row_number() OVER (
      PARTITION BY `Stock Item Key`
      ORDER BY `Last Edited When` DESC
    ) AS rn
  FROM edw_migration.bronze.fact_stockholding
) sh
  ON s.stock_item_id = sh.stock_item_key AND sh.rn = 1;

SELECT 'gold_mart_stock_movements_ok' AS check_name,
       (SELECT COUNT(*) FROM edw_migration.gold.mart_stock_movements) AS rows;
