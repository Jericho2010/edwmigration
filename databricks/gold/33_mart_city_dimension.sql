-- 33_mart_city_dimension.sql
-- Gold: mart_city_dimension — city snapshot.

CREATE OR REPLACE TABLE edw_migration.gold.mart_city_dimension AS
SELECT
  city_key,
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
