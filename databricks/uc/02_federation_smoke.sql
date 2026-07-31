-- 02_federation_smoke.sql
-- Fail-fast smoke test for the SOURCE layer. Run as the FIRST task of the
-- medallion job and as the first manual step after source setup.
--
-- Mode-agnostic by design: it checks edw_migration.source_fed.*, the contract
-- bronze actually consumes. Online that schema holds federation views over
-- wwi_dw_fed (so this still exercises the JDBC path); offline it holds seeded
-- Delta tables (databricks/offline/).
--
-- Uses Databricks SQL Scripting (BEGIN...END + DECLARE EXIT HANDLER).
-- See AI Dev Kit: databricks-dbsql/sql-scripting.md

BEGIN
  -- Variables must be declared before handlers (SQL scripting declaration order).
  DECLARE v_dim_customer BIGINT;
  DECLARE v_fact_sale BIGINT;
  DECLARE v_source_tables BIGINT;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Source smoke FAILED. Online remediation: (1) az sql db show --query status Online (2) sqlcmd SELECT 1 warmup (3) AllowDatabricksDemo firewall (4) secret edw-migration/azure-sql-password (5) docs/limits.md Free Edition outbound. Offline remediation: ./databricks/offline/seed_source.sh';
  END;

  -- 1. All six source tables/views present in source_fed
  SET v_source_tables = (
    SELECT COUNT(*)
    FROM edw_migration.information_schema.tables
    WHERE table_schema = 'source_fed'
      AND table_name IN ('dim_city', 'dim_customer', 'dim_stock_item',
                         'dim_date', 'fact_sale', 'fact_stockholding')
  );
  IF v_source_tables < 6 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'smoke FAILED: edw_migration.source_fed incomplete — run 01_federation_setup.sql (online) or seed_source.sh (offline)';
  END IF;

  -- 2. Facts non-empty (online: proves the federation JDBC path works)
  SET v_fact_sale = (SELECT COUNT(*) FROM edw_migration.source_fed.fact_sale);
  IF v_fact_sale IS NULL OR v_fact_sale = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'smoke FAILED: source_fed.fact_sale returned 0 rows (cold DB? bacpac not imported? seed not loaded?)';
  END IF;

  -- 3. Customer dimension non-empty
  SET v_dim_customer = (SELECT COUNT(*) FROM edw_migration.source_fed.dim_customer);
  IF v_dim_customer IS NULL OR v_dim_customer = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'smoke FAILED: source_fed.dim_customer is empty';
  END IF;

  SELECT 'smoke_ok' AS check_name,
         v_dim_customer AS dim_customer_rows,
         v_fact_sale AS fact_sale_rows;
END;
