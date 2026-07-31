-- reconcile.sql
-- Reconcile checks: prove the medallion matches the source.
-- Writes results to ops.reconcile_results.
--
-- Threshold: row counts must match exactly; orphan rate < 5%.
-- Databricks SQL: session vars via DECLARE VARIABLE + SET VAR; bare names.

DECLARE OR REPLACE VARIABLE v_run_id STRING;
DECLARE OR REPLACE VARIABLE v_ts TIMESTAMP;
SET VAR v_run_id = 'reconcile-' || date_format(current_timestamp(), 'yyyyMMddHHmmss');
SET VAR v_ts = current_timestamp();

-- ---------------------------------------------------------------------------
-- Check 1: bronze.dim_customer row count == source_fed.dim_customer row count
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'bronze_vs_source_dim_customer_rowcount' AS check_id,
  'bronze.dim_customer' AS table_name,
  CAST((SELECT COUNT(*) FROM edw_migration.source_fed.dim_customer) AS STRING) AS expected,
  CAST((SELECT COUNT(*) FROM edw_migration.bronze.dim_customer) AS STRING) AS actual,
  CAST(
    (SELECT COUNT(*) FROM edw_migration.source_fed.dim_customer)
    - (SELECT COUNT(*) FROM edw_migration.bronze.dim_customer)
  AS STRING) AS delta,
  CASE
    WHEN (SELECT COUNT(*) FROM edw_migration.source_fed.dim_customer)
       = (SELECT COUNT(*) FROM edw_migration.bronze.dim_customer)
    THEN 'pass' ELSE 'fail'
  END AS result,
  v_run_id AS run_id,
  v_ts AS ts
;

-- ---------------------------------------------------------------------------
-- Check 2: bronze.fact_sale row count == source_fed.fact_sale row count
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'bronze_vs_source_fact_sale_rowcount' AS check_id,
  'bronze.fact_sale' AS table_name,
  CAST((SELECT COUNT(*) FROM edw_migration.source_fed.fact_sale) AS STRING) AS expected,
  CAST((SELECT COUNT(*) FROM edw_migration.bronze.fact_sale) AS STRING) AS actual,
  CAST(
    (SELECT COUNT(*) FROM edw_migration.source_fed.fact_sale)
    - (SELECT COUNT(*) FROM edw_migration.bronze.fact_sale)
  AS STRING) AS delta,
  CASE
    WHEN (SELECT COUNT(*) FROM edw_migration.source_fed.fact_sale)
       = (SELECT COUNT(*) FROM edw_migration.bronze.fact_sale)
    THEN 'pass' ELSE 'fail'
  END AS result,
  v_run_id AS run_id,
  v_ts AS ts
;

-- ---------------------------------------------------------------------------
-- Check 3: gold.mart_daily_internet_sales is non-empty
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'gold_mart_daily_sales_nonempty' AS check_id,
  'gold.mart_daily_internet_sales' AS table_name,
  '>0' AS expected,
  CAST((SELECT COUNT(*) FROM edw_migration.gold.mart_daily_internet_sales) AS STRING) AS actual,
  CAST((SELECT COUNT(*) FROM edw_migration.gold.mart_daily_internet_sales) AS STRING) AS delta,
  CASE WHEN (SELECT COUNT(*) FROM edw_migration.gold.mart_daily_internet_sales) > 0
       THEN 'pass' ELSE 'fail' END AS result,
  v_run_id AS run_id,
  v_ts AS ts
;

-- ---------------------------------------------------------------------------
-- Check 4: gold.mart_customer_current row count == current SCD2 rows
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'gold_mart_customer_current_matches_scd2_current' AS check_id,
  'gold.mart_customer_current' AS table_name,
  CAST((SELECT COUNT(*) FROM edw_migration.silver.dim_customer_scd2 WHERE is_current) AS STRING) AS expected,
  CAST((SELECT COUNT(*) FROM edw_migration.gold.mart_customer_current) AS STRING) AS actual,
  CAST(
    (SELECT COUNT(*) FROM edw_migration.silver.dim_customer_scd2 WHERE is_current)
    - (SELECT COUNT(*) FROM edw_migration.gold.mart_customer_current)
  AS STRING) AS delta,
  CASE
    WHEN (SELECT COUNT(*) FROM edw_migration.silver.dim_customer_scd2 WHERE is_current)
       = (SELECT COUNT(*) FROM edw_migration.gold.mart_customer_current)
    THEN 'pass' ELSE 'fail'
  END AS result,
  v_run_id AS run_id,
  v_ts AS ts
;

-- ---------------------------------------------------------------------------
-- Check 5: silver.fact_sale orphan rate < 5%
-- Columns: check_id, table_name, expected, actual, delta, result, run_id, ts
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'silver_fact_sale_orphan_rate' AS check_id,
  'silver.fact_sale_orphan' AS table_name,
  '<5%' AS expected,
  CAST(
    CASE
      WHEN (SELECT COUNT(*) FROM edw_migration.silver.fact_sale)
         + (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) = 0 THEN 1.0
      ELSE (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) * 1.0
         / ((SELECT COUNT(*) FROM edw_migration.silver.fact_sale)
          + (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan))
    END AS STRING
  ) AS actual,
  CAST(
    CASE
      WHEN (SELECT COUNT(*) FROM edw_migration.silver.fact_sale)
         + (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) = 0 THEN 1.0
      ELSE (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) * 1.0
         / ((SELECT COUNT(*) FROM edw_migration.silver.fact_sale)
          + (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan))
    END AS STRING
  ) AS delta,
  CASE
    WHEN (SELECT COUNT(*) FROM edw_migration.silver.fact_sale)
       + (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) = 0 THEN 'fail'
    WHEN (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) * 100
       / ((SELECT COUNT(*) FROM edw_migration.silver.fact_sale)
        + (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan)) < 5
    THEN 'pass' ELSE 'fail'
  END AS result,
  v_run_id AS run_id,
  v_ts AS ts
;

-- ---------------------------------------------------------------------------
-- Check 6+: fixture expectations (ops.fixture_expectations)
-- Stage via databricks/tests/13_stage_fixture_expectations.sql first.
-- compare modes:
--   exact_when_expected_set — skip if expected IS NULL; else actual == expected
--   gte — actual >= expected
--   nonempty_when_missing_expected — if expected NULL then actual > 0 else exact
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY VIEW _fixture_eval AS
SELECT
  e.fixture_name,
  e.target_table,
  e.expected,
  e.compare,
  CASE e.target_table
    WHEN 'edw_migration.gold.mart_city_dimension'
      THEN (SELECT COUNT(*) FROM edw_migration.gold.mart_city_dimension)
    WHEN 'edw_migration.gold.mart_customer_current'
      THEN (SELECT COUNT(*) FROM edw_migration.gold.mart_customer_current)
    WHEN 'edw_migration.gold.mart_stock_movements'
      THEN (SELECT COUNT(*) FROM edw_migration.gold.mart_stock_movements)
    WHEN 'edw_migration.bronze.fact_sale'
      THEN (SELECT COUNT(*) FROM edw_migration.bronze.fact_sale)
    WHEN 'edw_migration.gold.mart_daily_internet_sales'
      THEN (SELECT COUNT(*) FROM edw_migration.gold.mart_daily_internet_sales)
    ELSE NULL
  END AS actual
FROM edw_migration.ops.fixture_expectations e;

INSERT INTO edw_migration.ops.reconcile_results
SELECT
  concat('fixture_', fixture_name) AS check_id,
  target_table AS table_name,
  CAST(expected AS STRING) AS expected,
  CAST(actual AS STRING) AS actual,
  CAST(
    CASE
      WHEN expected IS NULL THEN actual
      ELSE actual - expected
    END AS STRING
  ) AS delta,
  CASE
    WHEN actual IS NULL THEN 'fail'
    WHEN compare = 'exact_when_expected_set' AND expected IS NULL THEN 'pass'
    WHEN compare = 'exact_when_expected_set' AND actual = expected THEN 'pass'
    WHEN compare = 'gte' AND expected IS NOT NULL AND actual >= expected THEN 'pass'
    WHEN compare = 'nonempty_when_missing_expected' AND expected IS NULL AND actual > 0 THEN 'pass'
    WHEN compare = 'nonempty_when_missing_expected' AND expected IS NOT NULL AND actual = expected THEN 'pass'
    ELSE 'fail'
  END AS result,
  v_run_id AS run_id,
  v_ts AS ts
FROM _fixture_eval;

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
SELECT
  v_run_id AS run_id,
  SUM(CASE WHEN result = 'pass' THEN 1 ELSE 0 END) AS passed,
  SUM(CASE WHEN result = 'fail' THEN 1 ELSE 0 END) AS failed,
  COUNT(*) AS total
FROM edw_migration.ops.reconcile_results
WHERE run_id = v_run_id;
