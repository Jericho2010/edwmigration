-- Converted from: Integration.GetStockItemUpdates (sample agent output)
-- Classification: get
-- Target layer:   gold
-- Notes:          Sample offline artifact. Production conversion lives alongside
--                 the baseline job file databricks/gold/30_mart_daily_sales.sql.
--                 Agents write here so the job DAG baseline is not overwritten.

-- See baseline: ../../gold/30_mart_daily_sales.sql
SELECT 'sample_converted_daily_sales_stub' AS check_name;
