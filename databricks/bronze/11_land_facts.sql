-- 11_land_facts.sql
-- Bronze layer: 1:1 land of fact tables from source_fed into bronze.

DECLARE OR REPLACE VARIABLE v_batch_id STRING;
DECLARE OR REPLACE VARIABLE v_started TIMESTAMP;
SET v_batch_id = 'bronze-facts-' || date_format(current_timestamp(), 'yyyyMMddHHmmss');
SET v_started = current_timestamp();

-- ---------------------------------------------------------------------------
-- fact_sale
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE edw_migration.bronze.fact_sale AS
SELECT
  *,
  current_timestamp()                AS _bronze_loaded_at,
  'wwi_azure_sql'                     AS _source_system,
  ${v_batch_id}                       AS _batch_id
FROM edw_migration.source_fed.fact_sale;

INSERT INTO edw_migration.ops.load_control (table_name, batch_id, row_count, started_at, ended_at, status)
SELECT 'bronze.fact_sale', ${v_batch_id}, COUNT(*), ${v_started}, current_timestamp(), 'ok'
FROM edw_migration.bronze.fact_sale;

-- ---------------------------------------------------------------------------
-- fact_stockholding
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE edw_migration.bronze.fact_stockholding AS
SELECT
  *,
  current_timestamp()                AS _bronze_loaded_at,
  'wwi_azure_sql'                     AS _source_system,
  ${v_batch_id}                       AS _batch_id
FROM edw_migration.source_fed.fact_stockholding;

INSERT INTO edw_migration.ops.load_control (table_name, batch_id, row_count, started_at, ended_at, status)
SELECT 'bronze.fact_stockholding', ${v_batch_id}, COUNT(*), ${v_started}, current_timestamp(), 'ok'
FROM edw_migration.bronze.fact_stockholding;

SELECT 'bronze_facts_ok' AS check_name, ${v_batch_id} AS batch_id;
