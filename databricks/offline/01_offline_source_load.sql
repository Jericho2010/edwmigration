-- 01_offline_source_load.sql
-- Offline source mode: load the generated CSVs from the ops.offline_seed
-- volume into the typed source_fed tables.
--
-- INSERT with an explicit column list + read_files() casts. COPY INTO is
-- avoided deliberately: it name-merges the source schema and fails on
-- column-mapped Delta tables (DELTA_FAILED_TO_MERGE_FIELDS) — the source_fed
-- tables need 'delta.columnMapping.mode' = 'name' for WWI's spaced columns.
--
-- Run via: ./databricks/offline/seed_source.sh

INSERT INTO edw_migration.source_fed.dim_city
  (`City Key`, `WWI City ID`, `City`, `State Province`, `Country`,
   `Latest Recorded Population`, `Valid From`, `Valid To`)
SELECT
  CAST(`City Key` AS INT), CAST(`WWI City ID` AS INT), `City`,
  `State Province`, `Country`, CAST(`Latest Recorded Population` AS BIGINT),
  CAST(`Valid From` AS TIMESTAMP), CAST(`Valid To` AS TIMESTAMP)
FROM read_files('/Volumes/edw_migration/ops/offline_seed/dim_city.csv',
                format => 'csv', header => true);

INSERT INTO edw_migration.source_fed.dim_customer
  (`Customer Key`, `WWI Customer ID`, `Customer`, `Bill To Customer`,
   `Category`, `Buying Group`, `City`, `Valid From`, `Valid To`)
SELECT
  CAST(`Customer Key` AS INT), CAST(`WWI Customer ID` AS INT), `Customer`,
  `Bill To Customer`, `Category`, `Buying Group`, CAST(`City` AS INT),
  CAST(`Valid From` AS TIMESTAMP), CAST(`Valid To` AS TIMESTAMP)
FROM read_files('/Volumes/edw_migration/ops/offline_seed/dim_customer.csv',
                format => 'csv', header => true);

INSERT INTO edw_migration.source_fed.dim_stock_item
  (`Stock Item Key`, `WWI Stock Item ID`, `Stock Item`, `Brand`, `Size`,
   `Lead Time Days`, `Valid From`, `Valid To`)
SELECT
  CAST(`Stock Item Key` AS INT), CAST(`WWI Stock Item ID` AS INT),
  `Stock Item`, `Brand`, `Size`, CAST(`Lead Time Days` AS INT),
  CAST(`Valid From` AS TIMESTAMP), CAST(`Valid To` AS TIMESTAMP)
FROM read_files('/Volumes/edw_migration/ops/offline_seed/dim_stock_item.csv',
                format => 'csv', header => true);

INSERT INTO edw_migration.source_fed.dim_date
  (`Date`, `Day Number`, `Day`, `Month`, `Calendar Year`,
   `Calendar Month Number`, `Calendar Quarter`)
SELECT
  CAST(`Date` AS DATE), CAST(`Day Number` AS INT), `Day`, `Month`,
  CAST(`Calendar Year` AS INT), CAST(`Calendar Month Number` AS INT),
  CAST(`Calendar Quarter` AS INT)
FROM read_files('/Volumes/edw_migration/ops/offline_seed/dim_date.csv',
                format => 'csv', header => true);

INSERT INTO edw_migration.source_fed.fact_sale
  (`Sale Key`, `Invoice Date Key`, `Customer Key`, `Stock Item Key`,
   `Quantity`, `Unit Price`, `Total Including Tax`, `Profit`,
   `WWI Invoice ID`, `WWI Customer ID`, `WWI Stock Item ID`)
SELECT
  CAST(`Sale Key` AS BIGINT), CAST(`Invoice Date Key` AS DATE),
  CAST(`Customer Key` AS INT), CAST(`Stock Item Key` AS INT),
  CAST(`Quantity` AS INT), CAST(`Unit Price` AS DECIMAL(18,2)),
  CAST(`Total Including Tax` AS DECIMAL(18,2)), CAST(`Profit` AS DECIMAL(18,2)),
  CAST(`WWI Invoice ID` AS INT), CAST(`WWI Customer ID` AS INT),
  CAST(`WWI Stock Item ID` AS INT)
FROM read_files('/Volumes/edw_migration/ops/offline_seed/fact_sale.csv',
                format => 'csv', header => true);

INSERT INTO edw_migration.source_fed.fact_stockholding
  (`Stock Item Key`, `Quantity On Hand`, `Quantity Allocated`, `Last Edited When`)
SELECT
  CAST(`Stock Item Key` AS INT), CAST(`Quantity On Hand` AS INT),
  CAST(`Quantity Allocated` AS INT), CAST(`Last Edited When` AS TIMESTAMP)
FROM read_files('/Volumes/edw_migration/ops/offline_seed/fact_stockholding.csv',
                format => 'csv', header => true);

SELECT 'offline_source_load_ok' AS check_name;
