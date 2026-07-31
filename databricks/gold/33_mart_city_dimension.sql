-- 33_mart_city_dimension.sql
-- Gold layer: mart_city_dimension
-- Replaces Integration.GetCityUpdates (a result-set proc).
-- Pattern: CREATE OR REPLACE TABLE AS SELECT (full snapshot).

CREATE OR REPLACE TABLE edw_migration.gold.mart_city_dimension AS
SELECT
  city_id,
  city_name,
  state_province,
  country,
  latest_population,
  valid_from,
  valid_to
FROM edw_migration.silver.dim_city;

SELECT 'gold_mart_city_dimension_ok' AS check_name,
       (SELECT COUNT(*) FROM edw_migration.gold.mart_city_dimension) AS rows;
