-- Converted from: Integration.MigrateStagedStockHoldingData
-- Classification: migrate
-- Target layer:   gold
-- Patterns:       snapshot
-- Notes:          Current stock holding snapshot from bronze fact land.

CREATE OR REPLACE TABLE __UC_CATALOG__.gold.mart_stock_holding AS
SELECT
  `Stock Item Key` AS stock_item_key,
  `Quantity On Hand` AS quantity_on_hand,
  `Bin Location` AS bin_location,
  `Last Stocktake Quantity` AS last_stocktake_quantity,
  `Last Cost Price` AS last_cost_price,
  `Reorder Level` AS reorder_level,
  `Target Stock Level` AS target_stock_level,
  current_timestamp() AS as_of_ts
FROM __UC_CATALOG__.bronze.fact_stock_holding;

SELECT 'mart_stock_holding_ok' AS check_name, COUNT(*) AS rows
FROM __UC_CATALOG__.gold.mart_stock_holding;
