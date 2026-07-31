-- 01_federation_setup.sql
-- Bootstrap Unity Catalog + Lakehouse Federation to the Azure SQL EDW.
--
-- Prerequisites:
--   1. infra/azure/bootstrap.sh has run (RG, server, free DB, bacpac import, warmup).
--   2. Databricks secrets scope 'edw-migration' exists with secret 'azure-sql-password'
--      (created by bootstrap.sh).
--   3. Run this in a Databricks Free Edition workspace with Unity Catalog enabled
--      using a serverless SQL warehouse.
--   4. The Azure SQL DB must be Online (warm) before the foreign catalog is queried
--      (see 02_federation_smoke.sql).
--
-- Run via:
--   databricks sql execute --file databricks/uc/01_federation_setup.sql

-- ---------------------------------------------------------------------------
-- Catalog + schemas (managed, in edw_migration catalog)
-- ---------------------------------------------------------------------------
CREATE CATALOG IF NOT EXISTS edw_migration
  COMMENT 'EDW migration demo: bronze/silver/gold/ops managed tables';

CREATE SCHEMA IF NOT EXISTS edw_migration.source_fed
  COMMENT 'Convenience views over the wwi_dw_fed foreign catalog (stable snake_case names)';
CREATE SCHEMA IF NOT EXISTS edw_migration.bronze
  COMMENT '1:1 land from source_fed, with audit columns';
CREATE SCHEMA IF NOT EXISTS edw_migration.silver
  COMMENT 'Conformed types, SCD2 on customer, orphan-fact quarantine';
CREATE SCHEMA IF NOT EXISTS edw_migration.gold
  COMMENT '1:1 mapping to legacy Integration.* proc outcomes (marts)';
CREATE SCHEMA IF NOT EXISTS edw_migration.ops
  COMMENT 'Operational tables: load_control, migration_backlog, reconcile_results, agent_events';

-- ---------------------------------------------------------------------------
-- Federation connection to Azure SQL
-- Replace <AZ_SQL_SERVER> with your server name (e.g. sql-edwmig-XXXX).
-- The password is pulled from the Databricks secret scope created by bootstrap.sh.
-- ---------------------------------------------------------------------------
CREATE CONNECTION IF NOT EXISTS azure_sql_edw
  TYPE SQLSERVER
  OPTIONS (
    host '<AZ_SQL_SERVER>.database.windows.net',
    port '1433',
    user '<AZ_SQL_ADMIN>',
    password secret('edw-migration', 'azure-sql-password'),
    trustServerCertificate 'false'
  );

-- ---------------------------------------------------------------------------
-- Foreign catalog: read-only mirror of WideWorldImportersDW
-- NOTE: CREATE FOREIGN CATALOG does not support a COMMENT clause.
-- ---------------------------------------------------------------------------
CREATE FOREIGN CATALOG IF NOT EXISTS wwi_dw_fed
  USING CONNECTION azure_sql_edw
  OPTIONS (database 'WideWorldImportersDW');

-- ---------------------------------------------------------------------------
-- source_fed convenience views (stable snake_case names over wwi_dw_fed.*)
-- These insulate the medallion SQL from upstream schema/casing changes and
-- give the agents a clean, predictable surface to read from.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW edw_migration.source_fed.dim_customer AS
  SELECT * FROM wwi_dw_fed.dimension.customer;

CREATE OR REPLACE VIEW edw_migration.source_fed.dim_city AS
  SELECT * FROM wwi_dw_fed.dimension.city;

CREATE OR REPLACE VIEW edw_migration.source_fed.dim_stock_item AS
  SELECT * FROM wwi_dw_fed.dimension.`stock item`;

CREATE OR REPLACE VIEW edw_migration.source_fed.dim_date AS
  SELECT * FROM wwi_dw_fed.dimension.date;

CREATE OR REPLACE VIEW edw_migration.source_fed.fact_sale AS
  SELECT * FROM wwi_dw_fed.fact.sale;

CREATE OR REPLACE VIEW edw_migration.source_fed.fact_stockholding AS
  SELECT * FROM wwi_dw_fed.fact.stockholding;

-- ---------------------------------------------------------------------------
-- Smoke: prove the foreign catalog is reachable
-- ---------------------------------------------------------------------------
SELECT 'foreign_catalog_ok' AS check_name,
       COUNT(*) AS row_count
FROM wwi_dw_fed.fact.sale;
