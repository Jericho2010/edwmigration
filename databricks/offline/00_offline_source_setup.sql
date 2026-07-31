-- 00_offline_source_setup.sql
-- Offline source mode: replace Lakehouse Federation with native Delta tables
-- seeded from generated CSVs (databricks/offline/generate_seed.py).
--
-- Creates the same catalog/schemas as 01_federation_setup.sql, minus the
-- connection and foreign catalog, plus the upload volume and the six typed
-- source_fed tables. Column sets are the contract the silver layer consumes
-- (inventoried from the bacpac model.xml + silver/gold SQL).
--
-- NOTE: if a previous online run left source_fed VIEWS in place, drop the
-- catalog first (DROP CATALOG edw_migration CASCADE) — a view and a table
-- cannot share a name.
--
-- Run via: ./databricks/offline/seed_source.sh (generates, uploads, loads).

CREATE CATALOG IF NOT EXISTS edw_migration
  COMMENT 'EDW migration demo: bronze/silver/gold/ops managed tables';

CREATE SCHEMA IF NOT EXISTS edw_migration.source_fed
  COMMENT 'Offline mode: seeded Delta tables (stand-in for federation views)';
CREATE SCHEMA IF NOT EXISTS edw_migration.bronze
  COMMENT '1:1 land from source_fed, with audit columns';
CREATE SCHEMA IF NOT EXISTS edw_migration.silver
  COMMENT 'Conformed types, SCD2 on customer, orphan-fact quarantine';
CREATE SCHEMA IF NOT EXISTS edw_migration.gold
  COMMENT 'Marts 1:1 with legacy Integration.* proc outcomes';
CREATE SCHEMA IF NOT EXISTS edw_migration.ops
  COMMENT 'load_control, migration_backlog, reconcile_results, agent_events';

GRANT USE CATALOG ON CATALOG edw_migration TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.source_fed TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.bronze TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.silver TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.gold TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.ops TO `account users`;
GRANT SELECT ON CATALOG edw_migration TO `account users`;

CREATE VOLUME IF NOT EXISTS edw_migration.ops.offline_seed
  COMMENT 'Landing zone for generated seed CSVs (offline source mode)';

CREATE OR REPLACE TABLE edw_migration.source_fed.dim_city (
  `City Key` INT, `WWI City ID` INT, `City` STRING, `State Province` STRING,
  `Country` STRING, `Latest Recorded Population` BIGINT,
  `Valid From` TIMESTAMP, `Valid To` TIMESTAMP
) USING DELTA
TBLPROPERTIES ('delta.columnMapping.mode' = 'name');

CREATE OR REPLACE TABLE edw_migration.source_fed.dim_customer (
  `Customer Key` INT, `WWI Customer ID` INT, `Customer` STRING,
  `Bill To Customer` STRING, `Category` STRING, `Buying Group` STRING,
  `City` INT, `Valid From` TIMESTAMP, `Valid To` TIMESTAMP
) USING DELTA
TBLPROPERTIES ('delta.columnMapping.mode' = 'name');

CREATE OR REPLACE TABLE edw_migration.source_fed.dim_stock_item (
  `Stock Item Key` INT, `WWI Stock Item ID` INT, `Stock Item` STRING,
  `Brand` STRING, `Size` STRING, `Lead Time Days` INT,
  `Valid From` TIMESTAMP, `Valid To` TIMESTAMP
) USING DELTA
TBLPROPERTIES ('delta.columnMapping.mode' = 'name');

CREATE OR REPLACE TABLE edw_migration.source_fed.dim_date (
  `Date` DATE, `Day Number` INT, `Day` STRING, `Month` STRING,
  `Calendar Year` INT, `Calendar Month Number` INT, `Calendar Quarter` INT
) USING DELTA
TBLPROPERTIES ('delta.columnMapping.mode' = 'name');

CREATE OR REPLACE TABLE edw_migration.source_fed.fact_sale (
  `Sale Key` BIGINT, `Invoice Date Key` DATE, `Customer Key` INT,
  `Stock Item Key` INT, `Quantity` INT, `Unit Price` DECIMAL(18,2),
  `Total Including Tax` DECIMAL(18,2), `Profit` DECIMAL(18,2),
  `WWI Invoice ID` INT, `WWI Customer ID` INT, `WWI Stock Item ID` INT
) USING DELTA
TBLPROPERTIES ('delta.columnMapping.mode' = 'name');

CREATE OR REPLACE TABLE edw_migration.source_fed.fact_stockholding (
  `Stock Item Key` INT, `Quantity On Hand` INT, `Quantity Allocated` INT,
  `Last Edited When` TIMESTAMP
) USING DELTA
TBLPROPERTIES ('delta.columnMapping.mode' = 'name');

SELECT 'offline_source_setup_ok' AS check_name;
