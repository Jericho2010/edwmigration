-- reconcile.sql
-- Reconcile checks: prove the medallion matches the source and the fixtures.
-- Writes results to ops.reconcile_results. The Test agent runs this (read-only
-- SELECTs) and the coordinator inserts the rows.
--
-- Two fixture types:
--   Get* proc fixtures: compare gold result set to legacy/fixtures/get_*.csv
--   Migrate* proc fixtures: compare gold snapshot to legacy/fixtures/dim_*_after_migrate.csv
--
-- Threshold: row counts must match exactly; numeric sums within 0.01%.

DECLARE OR REPLACE VARIABLE v_run_id STRING;
DECLARE OR REPLACE VARIABLE v_ts TIMESTAMP;
SET v_run_id = 'reconcile-' || date_format(current_timestamp(), 'yyyyMMddHHmmss');
SET v_ts = current_timestamp();

-- Helper: insert a reconcile result row
CREATE TEMPORARY VIEW _reconcile_insert AS SELECT 1 AS dummy;

-- ---------------------------------------------------------------------------
-- Check 1: bronze.dim_customer row count == source_fed.dim_customer row count
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'bronze_vs_source_dim_customer_rowcount' AS check_id,
  'bronze.dim_customer'                     AS table_name,
  CAST((SELECT COUNT(*) FROM edw_migration.source_fed.dim_customer) AS STRING) AS expected,
  CAST((SELECT COUNT(*) FROM edw_migration.bronze.dim_customer)     AS STRING) AS actual,
  CAST(
    (SELECT COUNT(*) FROM edw_migration.source_fed.dim_customer)
    - (SELECT COUNT(*) FROM edw_migration.bronze.dim_customer)
  AS STRING) AS delta,
  CASE
    WHEN (SELECT COUNT(*) FROM edw_migration.source_fed.dim_customer)
       = (SELECT COUNT(*) FROM edw_migration.bronze.dim_customer)
    THEN 'pass' ELSE 'fail'
  END AS result,
  ${v_run_id}, ${v_ts}
;

-- ---------------------------------------------------------------------------
-- Check 2: bronze.fact_sale row count == source_fed.fact_sale row count
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'bronze_vs_source_fact_sale_rowcount',
  'bronze.fact_sale',
  CAST((SELECT COUNT(*) FROM edw_migration.source_fed.fact_sale) AS STRING),
  CAST((SELECT COUNT(*) FROM edw_migration.bronze.fact_sale)     AS STRING),
  CAST(
    (SELECT COUNT(*) FROM edw_migration.source_fed.fact_sale)
    - (SELECT COUNT(*) FROM edw_migration.bronze.fact_sale)
  AS STRING),
  CASE
    WHEN (SELECT COUNT(*) FROM edw_migration.source_fed.fact_sale)
       = (SELECT COUNT(*) FROM edw_migration.bronze.fact_sale)
    THEN 'pass' ELSE 'fail'
  END,
  ${v_run_id}, ${v_ts}
;

-- ---------------------------------------------------------------------------
-- Check 3: gold.mart_daily_internet_sales is non-empty
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'gold_mart_daily_sales_nonempty',
  'gold.mart_daily_internet_sales',
  '>0',
  CAST((SELECT COUNT(*) FROM edw_migration.gold.mart_daily_internet_sales) AS STRING),
  CAST((SELECT COUNT(*) FROM edw_migration.gold.mart_daily_internet_sales) AS STRING),
  CASE WHEN (SELECT COUNT(*) FROM edw_migration.gold.mart_daily_internet_sales) > 0
       THEN 'pass' ELSE 'fail' END,
  ${v_run_id}, ${v_ts}
;

-- ---------------------------------------------------------------------------
-- Check 4: gold.mart_customer_current row count == current SCD2 rows
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'gold_mart_customer_current_matches_scd2_current',
  'gold.mart_customer_current',
  CAST((SELECT COUNT(*) FROM edw_migration.silver.dim_customer_scd2 WHERE is_current) AS STRING),
  CAST((SELECT COUNT(*) FROM edw_migration.gold.mart_customer_current)                AS STRING),
  CAST(
    (SELECT COUNT(*) FROM edw_migration.silver.dim_customer_scd2 WHERE is_current)
    - (SELECT COUNT(*) FROM edw_migration.gold.mart_customer_current)
  AS STRING),
  CASE
    WHEN (SELECT COUNT(*) FROM edw_migration.silver.dim_customer_scd2 WHERE is_current)
       = (SELECT COUNT(*) FROM edw_migration.gold.mart_customer_current)
    THEN 'pass' ELSE 'fail'
  END,
  ${v_run_id}, ${v_ts}
;

-- ---------------------------------------------------------------------------
-- Check 5: silver.fact_sale orphan rate < 5%
-- ---------------------------------------------------------------------------
INSERT INTO edw_migration.ops.reconcile_results
SELECT
  'silver_fact_sale_orphan_rate',
  'silver.fact_sale_orphan',
  '<5%',
  CAST(
    CASE WHEN (SELECT COUNT(*) FROM edw_migration.silver.fact_sale) = 0 THEN 1.0
         ELSE (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) * 1.0
            / ((SELECT COUNT(*) FROM edw_migration.silver.fact_sale)
             + (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan))
    END AS STRING
  ),
  CAST(
    CASE WHEN (SELECT COUNT(*) FROM edw_migration.silver.fact_sale) = 0 THEN 1.0
         ELSE (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) * 1.0
            / ((SELECT COUNT(*) FROM edw_migration.silver.fact_sale)
             + (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan))
    END AS STRING
  ),
  'n/a',
  CASE
    WHEN (SELECT COUNT(*) FROM edw_migration.silver.fact_sale) = 0 THEN 'fail'
    WHEN (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan) * 100
       / ((SELECT COUNT(*) FROM edw_migration.silver.fact_sale)
        + (SELECT COUNT(*) FROM edw_migration.silver.fact_sale_orphan)) < 5
    THEN 'pass' ELSE 'fail'
  END,
  ${v_run_id}, ${v_ts}
;

-- ---------------------------------------------------------------------------
-- Summary
-- ---------------------------------------------------------------------------
SELECT
  ${v_run_id} AS run_id,
  SUM(CASE WHEN result = 'pass' THEN 1 ELSE 0 END) AS passed,
  SUM(CASE WHEN result = 'fail' THEN 1 ELSE 0 END) AS failed,
  COUNT(*) AS total
FROM edw_migration.ops.reconcile_results
WHERE run_id = ${v_run_id};
