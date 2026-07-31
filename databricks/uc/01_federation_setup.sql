-- 01_federation_setup.sql
-- Bootstrap Unity Catalog + Lakehouse Federation to the Azure SQL EDW.
--
-- BEFORE RUNNING: replace placeholders (or use agents/tools/render_federation_sql.sh):
--   {{AZ_SQL_HOST}}  e.g. sql-edwmig-xxx.database.windows.net
--   {{AZ_SQL_ADMIN}} e.g. edwadmin
--
-- Prerequisites:
--   1. infra/azure/bootstrap.sh completed (DB warm, bacpac imported).
--   2. Secret scope edw-migration with secret azure-sql-password.
--   3. Serverless SQL warehouse on Free Edition with UC enabled.
--
-- Run:
--   ./agents/tools/render_federation_sql.sh | ./agents/tools/run_sql.sh --sql "$(cat)"
--   OR after substitution: ./agents/tools/run_sql.sh --file /tmp/01_federation_setup.rendered.sql

CREATE CATALOG IF NOT EXISTS edw_migration
  COMMENT 'EDW migration demo: bronze/silver/gold/ops managed tables';

CREATE SCHEMA IF NOT EXISTS edw_migration.source_fed
  COMMENT 'Convenience views over wwi_dw_fed (stable snake_case names)';
CREATE SCHEMA IF NOT EXISTS edw_migration.bronze
  COMMENT '1:1 land from source_fed, with audit columns';
CREATE SCHEMA IF NOT EXISTS edw_migration.silver
  COMMENT 'Conformed types, SCD2 on customer, orphan-fact quarantine';
CREATE SCHEMA IF NOT EXISTS edw_migration.gold
  COMMENT 'Marts 1:1 with legacy Integration.* proc outcomes';
CREATE SCHEMA IF NOT EXISTS edw_migration.ops
  COMMENT 'load_control, migration_backlog, reconcile_results, agent_events';

CREATE CONNECTION IF NOT EXISTS azure_sql_edw
  TYPE SQLSERVER
  OPTIONS (
    host '{{AZ_SQL_HOST}}',
    port '1433',
    user '{{AZ_SQL_ADMIN}}',
    password secret('edw-migration', 'azure-sql-password'),
    trustServerCertificate 'false'
  );

CREATE FOREIGN CATALOG IF NOT EXISTS wwi_dw_fed
  USING CONNECTION azure_sql_edw
  OPTIONS (database 'WideWorldImportersDW');

-- Governance (demo): grant current account + users group minimal access.
-- Adjust principal names for your workspace.
GRANT USE CATALOG ON CATALOG edw_migration TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.source_fed TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.bronze TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.silver TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.gold TO `account users`;
GRANT USE SCHEMA ON SCHEMA edw_migration.ops TO `account users`;
GRANT SELECT ON CATALOG edw_migration TO `account users`;
GRANT USE CONNECTION ON CONNECTION azure_sql_edw TO `account users`;
GRANT USE CATALOG ON CATALOG wwi_dw_fed TO `account users`;
GRANT SELECT ON CATALOG wwi_dw_fed TO `account users`;

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
  SELECT * FROM wwi_dw_fed.fact.`stock holding`;

SELECT 'federation_setup_ok' AS check_name,
       COUNT(*) AS fact_sale_rows
FROM wwi_dw_fed.fact.sale;
