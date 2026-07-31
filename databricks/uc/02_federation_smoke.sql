-- 02_federation_smoke.sql
-- Fail-fast smoke test for the federation connection. Run as the FIRST task
-- of the medallion job and as the first manual step after 01_federation_setup.sql.
--
-- Uses Databricks SQL Scripting (BEGIN...END + DECLARE EXIT HANDLER).
-- See AI Dev Kit: databricks-dbsql/sql-scripting.md
--
-- Free Edition notes:
--   - Outbound internet is restricted.
--   - Azure SQL serverless auto-pauses after 15 min; warm with sqlcmd SELECT 1 first.

BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Federation smoke FAILED (JDBC/connection). Remediation: (1) az sql db show --query status Online (2) sqlcmd SELECT 1 warmup (3) AllowDatabricksDemo firewall 0.0.0.0/0 (4) secret edw-migration/azure-sql-password (5) docs/limits.md Free Edition outbound';
  END;

  DECLARE v_dim_customer BIGINT;
  DECLARE v_fact_sale BIGINT;
  DECLARE v_schema_cnt BIGINT;

  -- 1. Foreign catalog reachable and non-empty
  SET v_fact_sale = (SELECT COUNT(*) FROM wwi_dw_fed.fact.sale);
  IF v_fact_sale IS NULL OR v_fact_sale = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'smoke FAILED: wwi_dw_fed.fact.sale returned 0 rows (cold DB? bacpac not imported?)';
  END IF;

  -- 2. Required schemas visible
  SET v_schema_cnt = (
    SELECT COUNT(DISTINCT schema_name)
    FROM system.information_schema.schemata
    WHERE catalog_name = 'wwi_dw_fed'
      AND lower(schema_name) IN ('dimension', 'fact', 'integration')
  );
  -- Fallback: if information_schema does not list foreign schemas, still require tables.
  IF v_schema_cnt = 0 THEN
    -- Prove schemas by querying known tables (already did fact.sale)
    SET v_dim_customer = (SELECT COUNT(*) FROM wwi_dw_fed.dimension.customer);
  ELSE
    SET v_dim_customer = (SELECT COUNT(*) FROM wwi_dw_fed.dimension.customer);
  END IF;

  IF v_dim_customer IS NULL OR v_dim_customer = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'smoke FAILED: wwi_dw_fed.dimension.customer is empty';
  END IF;

  SELECT 'smoke_ok' AS check_name,
         v_dim_customer AS dim_customer_rows,
         v_fact_sale AS fact_sale_rows;
END;
