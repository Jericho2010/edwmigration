-- 01_federation_setup.sql
-- Generic UC + Lakehouse Federation bootstrap (no per-table coupling).
-- Placeholders filled by agents/tools/render_sql.sh:
--   __UC_CATALOG__  __FOREIGN_CATALOG__  __CONNECTION_NAME__  __SECRET_SCOPE__
--   {{AZ_SQL_HOST}}  {{AZ_SQL_ADMIN}}  {{AZ_SQL_DB}}
--
-- Requires: CREATE CONNECTION + CREATE CATALOG (or metastore admin).
-- Password: secret('__SECRET_SCOPE__', 'azure-sql-password').

CREATE CATALOG IF NOT EXISTS __UC_CATALOG__
  COMMENT 'EDW migration managed catalog: source_fed/bronze/silver/gold/ops';

CREATE SCHEMA IF NOT EXISTS __UC_CATALOG__.source_fed
  COMMENT 'Stable landing names over the foreign catalog (generated per inventory)';
CREATE SCHEMA IF NOT EXISTS __UC_CATALOG__.bronze
  COMMENT '1:1 land from source with audit columns';
CREATE SCHEMA IF NOT EXISTS __UC_CATALOG__.silver
  COMMENT 'Conformed dims/facts from converted procs + land';
CREATE SCHEMA IF NOT EXISTS __UC_CATALOG__.gold
  COMMENT 'Marts produced by converted procs';
CREATE SCHEMA IF NOT EXISTS __UC_CATALOG__.ops
  COMMENT 'Inventory, backlog, reconcile, agent_events';

CREATE CONNECTION IF NOT EXISTS __CONNECTION_NAME__
  TYPE SQLSERVER
  OPTIONS (
    host '{{AZ_SQL_HOST}}',
    port '1433',
    user '{{AZ_SQL_ADMIN}}',
    password secret('__SECRET_SCOPE__', 'azure-sql-password'),
    trustServerCertificate 'false'
  );

CREATE FOREIGN CATALOG IF NOT EXISTS __FOREIGN_CATALOG__
  USING CONNECTION __CONNECTION_NAME__
  OPTIONS (database '{{AZ_SQL_DB}}');

GRANT USE CATALOG ON CATALOG __UC_CATALOG__ TO `account users`;
GRANT USE SCHEMA ON SCHEMA __UC_CATALOG__.source_fed TO `account users`;
GRANT USE SCHEMA ON SCHEMA __UC_CATALOG__.bronze TO `account users`;
GRANT USE SCHEMA ON SCHEMA __UC_CATALOG__.silver TO `account users`;
GRANT USE SCHEMA ON SCHEMA __UC_CATALOG__.gold TO `account users`;
GRANT USE SCHEMA ON SCHEMA __UC_CATALOG__.ops TO `account users`;
GRANT SELECT ON CATALOG __UC_CATALOG__ TO `account users`;
GRANT USE CONNECTION ON CONNECTION __CONNECTION_NAME__ TO `account users`;
GRANT USE CATALOG ON CATALOG __FOREIGN_CATALOG__ TO `account users`;
GRANT SELECT ON CATALOG __FOREIGN_CATALOG__ TO `account users`;

SELECT 'federation_setup_ok' AS check_name,
       current_catalog() AS current_catalog;
