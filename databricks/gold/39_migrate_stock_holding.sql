-- Converted from: Integration.MigrateStagedStockHoldingData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   gold
-- Patterns:       snapshot, truncate_reload, key_lookup
-- Notes:          Land-first truncate/reload of Fact.Stock Holding from
--                 bronze.integration_stockholding_staging. Resolves Stock Item Key
--                 via latest Valid To on bronze.dim_stock_item (COALESCE → 0).
--                 Open Integration.Lineage row for 'Stock Holding' marked complete;
--                 Integration.ETL Cutoff advanced from lineage Source System Cutoff.
--                 Multi-table BEGIN TRAN expressed as sequential Delta statements
--                 (no cross-table atomicity).

-- Open lineage key for Stock Holding (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _stock_holding_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Stock Holding'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Latest Stock Item Key per WWI Stock Item ID (ORDER BY Valid To DESC).
CREATE OR REPLACE TEMP VIEW _stock_item_key_lookup AS
SELECT
  `WWI Stock Item ID` AS wwi_stock_item_id,
  `Stock Item Key` AS stock_item_key
FROM (
  SELECT
    `WWI Stock Item ID`,
    `Stock Item Key`,
    ROW_NUMBER() OVER (
      PARTITION BY `WWI Stock Item ID`
      ORDER BY `Valid To` DESC
    ) AS rn
  FROM __UC_CATALOG__.bronze.dim_stock_item
) ranked
WHERE rn = 1;

-- Truncate + reload Fact.Stock Holding from staging with resolved keys + lineage.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.fact_stock_holding AS
SELECT
  COALESCE(lk.stock_item_key, 0) AS stock_item_key,
  s.`Quantity On Hand` AS quantity_on_hand,
  s.`Bin Location` AS bin_location,
  s.`Last Stocktake Quantity` AS last_stocktake_quantity,
  s.`Last Cost Price` AS last_cost_price,
  s.`Reorder Level` AS reorder_level,
  s.`Target Stock Level` AS target_stock_level,
  l.lineage_key
FROM __UC_CATALOG__.bronze.integration_stockholding_staging s
LEFT JOIN _stock_item_key_lookup lk
  ON s.`WWI Stock Item ID` = lk.wwi_stock_item_id
LEFT JOIN _stock_holding_lineage l ON TRUE;

-- Mark Stock Holding lineage row complete (silver/gold side copy; bronze land stays as-landed).
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
    ELSE CAST(b.`Was Successful` AS BOOLEAN)
  END AS was_successful,
  b.`Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage b
LEFT JOIN _stock_holding_lineage l ON TRUE;

-- Advance ETL cutoff for Stock Holding from lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Stock Holding' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _stock_holding_lineage l ON TRUE;

SELECT 'fact_stock_holding_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.fact_stock_holding) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.integration_lineage
        WHERE table_name = 'Stock Holding' AND was_successful IS TRUE) AS lineage_ok_rows;
