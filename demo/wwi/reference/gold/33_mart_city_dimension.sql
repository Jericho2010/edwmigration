-- 33_mart_city_dimension.sql
-- Gold: mart_city_dimension — city snapshot.

CREATE OR REPLACE TABLE __UC_CATALOG__.gold.mart_city_dimension AS
SELECT
  city_key,
  city_id,
  city_name,
  state_province,
  country,
  latest_population,
  valid_from,
  valid_to
FROM __UC_CATALOG__.silver.dim_city;

SELECT 'gold_mart_city_dimension_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.mart_city_dimension) AS rows;
