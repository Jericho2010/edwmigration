-- 10_land_dims.sql
-- Bronze layer: 1:1 land of dimension tables from source_fed into bronze.
-- Pattern: CREATE OR REPLACE TABLE ... AS SELECT ... with audit columns.
-- Databricks SQL Scripting: session variables via DECLARE VARIABLE + SET VAR;
-- reference variables by bare name (not ${...}).

DECLARE OR REPLACE VARIABLE v_batch_id STRING;
DECLARE OR REPLACE VARIABLE v_started TIMESTAMP;
SET VAR v_batch_id = 'bronze-dims-' || date_format(current_timestamp(), 'yyyyMMddHHmmss');
SET VAR v_started = current_timestamp();

-- ---------------------------------------------------------------------------
-- dim_customer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE edw_migration.bronze.dim_customer AS
SELECT
  *,
  current_timestamp() AS _bronze_loaded_at,
  'wwi_azure_sql' AS _source_system,
  v_batch_id AS _batch_id
FROM edw_migration.source_fed.dim_customer;

INSERT INTO edw_migration.ops.load_control (table_name, batch_id, row_count, started_at, ended_at, status)
SELECT 'bronze.dim_customer', v_batch_id, COUNT(*), v_started, current_timestamp(), 'ok'
FROM edw_migration.bronze.dim_customer;

-- ---------------------------------------------------------------------------
-- dim_city
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE edw_migration.bronze.dim_city AS
SELECT
  *,
  current_timestamp() AS _bronze_loaded_at,
  'wwi_azure_sql' AS _source_system,
  v_batch_id AS _batch_id
FROM edw_migration.source_fed.dim_city;

INSERT INTO edw_migration.ops.load_control (table_name, batch_id, row_count, started_at, ended_at, status)
SELECT 'bronze.dim_city', v_batch_id, COUNT(*), v_started, current_timestamp(), 'ok'
FROM edw_migration.bronze.dim_city;

-- ---------------------------------------------------------------------------
-- dim_stock_item
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE edw_migration.bronze.dim_stock_item AS
SELECT
  *,
  current_timestamp() AS _bronze_loaded_at,
  'wwi_azure_sql' AS _source_system,
  v_batch_id AS _batch_id
FROM edw_migration.source_fed.dim_stock_item;

INSERT INTO edw_migration.ops.load_control (table_name, batch_id, row_count, started_at, ended_at, status)
SELECT 'bronze.dim_stock_item', v_batch_id, COUNT(*), v_started, current_timestamp(), 'ok'
FROM edw_migration.bronze.dim_stock_item;

-- ---------------------------------------------------------------------------
-- dim_date
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE edw_migration.bronze.dim_date AS
SELECT
  *,
  current_timestamp() AS _bronze_loaded_at,
  'wwi_azure_sql' AS _source_system,
  v_batch_id AS _batch_id
FROM edw_migration.source_fed.dim_date;

INSERT INTO edw_migration.ops.load_control (table_name, batch_id, row_count, started_at, ended_at, status)
SELECT 'bronze.dim_date', v_batch_id, COUNT(*), v_started, current_timestamp(), 'ok'
FROM edw_migration.bronze.dim_date;

SELECT 'bronze_dims_ok' AS check_name, v_batch_id AS batch_id;
