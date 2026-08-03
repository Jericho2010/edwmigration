-- 01_federation_setup.sql
-- Generic UC + Lakehouse Federation bootstrap (no per-table coupling).
-- Placeholders filled by agents/tools/render_sql.sh:
--   __UC_CATALOG__  __FOREIGN_CATALOG__  __CONNECTION_NAME__  __SECRET_SCOPE__
--   __CONNECTION_TYPE__  __PASSWORD_SECRET_KEY__
--   {{SOURCE_HOST}}  {{SOURCE_PORT}}  {{SOURCE_USER}}  {{SOURCE_DATABASE}}
--
-- Requires: CREATE CONNECTION + CREATE CATALOG (or metastore admin).
-- Password: secret('__SECRET_SCOPE__', '__PASSWORD_SECRET_KEY__').

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

-- __FEDERATION_CONNECTION_BLOCK__ (injected by render_sql.sh for SQLSERVER vs MYSQL)

CREATE FOREIGN CATALOG IF NOT EXISTS __FOREIGN_CATALOG__
  USING CONNECTION __CONNECTION_NAME__
  OPTIONS (database '{{SOURCE_DATABASE}}');

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
