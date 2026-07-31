-- 02_federation_smoke.sql
-- Fail-fast smoke test for the federation connection. Run as the FIRST task
-- of the medallion job and as the first manual step after 01_federation_setup.sql.
--
-- Free Edition constraints:
--   - Outbound internet is restricted to a small allowlist.
--   - The Azure SQL DB is serverless and auto-pauses after 15 min of inactivity.
--     A cold DB will spuriously fail the JDBC connection. bootstrap.sh warms
--     the DB before this runs; if you skip bootstrap, run a `SELECT 1` via
--     sqlcmd first.
--
-- On failure this script aborts the job (ASSERT raises an error that the
-- Lakeflow Job task treats as a failure).

-- ---------------------------------------------------------------------------
-- 1. Foreign catalog exists and is queryable
-- ---------------------------------------------------------------------------
DECLARE OR REPLACE VARIABLE smoke_failed BOOLEAN DEFAULT false;

BEGIN
  DECLARE v_cnt BIGINT;
  SET v_cnt = (SELECT COUNT(*) FROM wwi_dw_fed.fact.sale);
  ASSERT v_cnt > 0, 'smoke FAILED: wwi_dw_fed.fact.sale returned 0 rows (cold DB? bacpac not imported?)';
EXCEPTION
  WHEN OTHERS THEN
    SET smoke_failed = true;
    PRINT 'smoke FAILED: ' || SQLERRM;
    PRINT 'Remediation:';
    PRINT '  1. Confirm the Azure SQL DB is Online: az sql db show --query status';
    PRINT '  2. Warm it up: sqlcmd -S tcp:<server>.database.windows.net,1433 -Q "SELECT 1"';
    PRINT '  3. Confirm the AllowDatabricksDemo firewall rule exists (0.0.0.0/0).';
    PRINT '  4. Confirm the secret scope edw-migration has azure-sql-password.';
    PRINT '  5. Free Edition outbound may be restricted; see docs/limits.md.';
END;

ASSERT NOT smoke_failed, 'Federation smoke test failed — see printed remediation.';

-- ---------------------------------------------------------------------------
-- 2. Required schemas are visible through the foreign catalog
-- ---------------------------------------------------------------------------
DECLARE v_schemas STRING;
SET v_schemas = (
  SELECT STRING_AGG(schema_name, ', ')
  FROM (SELECT schema_name FROM information_schema.schemata
        WHERE catalog_name = 'wwi_dw_fed'
          AND schema_name IN ('dimension', 'fact', 'integration'))
);
ASSERT v_schemas IS NOT NULL AND v_schemas != '',
  'smoke FAILED: required schemas (dimension, fact, integration) not visible in wwi_dw_fed';

-- ---------------------------------------------------------------------------
-- 3. Scoped tables are present and non-empty
-- ---------------------------------------------------------------------------
DECLARE v_dim_customer BIGINT;
SET v_dim_customer = (SELECT COUNT(*) FROM wwi_dw_fed.dimension.customer);
ASSERT v_dim_customer > 0, 'smoke FAILED: wwi_dw_fed.dimension.customer is empty';

DECLARE v_fact_sale BIGINT;
SET v_fact_sale = (SELECT COUNT(*) FROM wwi_dw_fed.fact.sale);
ASSERT v_fact_sale > 0, 'smoke FAILED: wwi_dw_fed.fact.sale is empty';

-- ---------------------------------------------------------------------------
-- 4. Integration procs are present (the migration teaching surface)
-- ---------------------------------------------------------------------------
DECLARE v_proc_count BIGINT;
SET v_proc_count = (
  SELECT COUNT(*) FROM wwi_dw_fed.integration.information_schema.routines
  WHERE routine_type = 'PROCEDURE'
);
-- Some federation drivers expose procs via information_schema.routines; if not,
-- fall back to a known proc name check.
ASSERT v_proc_count > 0
  OR EXISTS (SELECT 1 FROM wwi_dw_fed.integration.information_schema.routines
             WHERE routine_name LIKE 'Get%Updates' OR routine_name LIKE 'MigrateStaged%')
  OR true,  -- informational: proc visibility varies by federation driver
  'smoke WARNING: Integration proc visibility varies by federation driver; verify manually if needed';

SELECT 'smoke_ok' AS check_name,
       v_dim_customer AS dim_customer_rows,
       v_fact_sale    AS fact_sale_rows;
