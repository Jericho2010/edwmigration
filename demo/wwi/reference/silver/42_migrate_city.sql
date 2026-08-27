-- Converted from: Integration.MigrateStagedCityData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   silver
-- Patterns:       scd2, snapshot
-- Notes:          Land-first SCD2 apply from bronze.integration_city_staging onto
--                 bronze.dim_city. Close current versions (Valid To = end-of-time)
--                 whose WWI City ID appears in staging, then append staging rows
--                 with the open City lineage_key. IDENTITY City Key is synthesized
--                 as max(existing)+row_number for new versions only. Lineage
--                 completion and ETL cutoff live on silver copies (Federation is
--                 read-only; BEGIN TRAN is sequential Delta, not multi-table atomic).

-- Open lineage key for City (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _city_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'City'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Per-business-key close-off timestamp from staging (MIN Valid From).
CREATE OR REPLACE TEMP VIEW _city_rows_to_close AS
SELECT
  `WWI City ID` AS wwi_city_id,
  MIN(`Valid From`) AS valid_from
FROM __UC_CATALOG__.bronze.integration_city_staging
GROUP BY `WWI City ID`;

-- Rebuild silver dim: close-off matched current rows, keep others, append staging inserts.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.dim_city AS
WITH end_of_time AS (
  SELECT CAST('9999-12-31 23:59:59.999999' AS TIMESTAMP) AS ts
),
existing_closed AS (
  SELECT
    d.`City Key` AS city_key,
    d.`WWI City ID` AS city_id,
    d.`City` AS city_name,
    d.`State Province` AS state_province,
    d.`Country` AS country,
    d.`Continent` AS continent,
    d.`Sales Territory` AS sales_territory,
    d.`Region` AS region,
    d.`Subregion` AS subregion,
    d.`Location` AS location,
    d.`Latest Recorded Population` AS latest_population,
    d.`Valid From` AS valid_from,
    CASE
      WHEN rtco.wwi_city_id IS NOT NULL
           AND (
             d.`Valid To` = e.ts
             OR CAST(d.`Valid To` AS DATE) = DATE '9999-12-31'
           )
        THEN rtco.valid_from
      ELSE d.`Valid To`
    END AS valid_to,
    d.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.dim_city d
  CROSS JOIN end_of_time e
  LEFT JOIN _city_rows_to_close rtco
    ON d.`WWI City ID` = rtco.wwi_city_id
),
max_key AS (
  SELECT COALESCE(MAX(city_key), 0) AS max_city_key
  FROM existing_closed
),
new_versions AS (
  SELECT
    CAST(mk.max_city_key + ROW_NUMBER() OVER (
      ORDER BY s.`WWI City ID`, s.`Valid From`
    ) AS BIGINT) AS city_key,
    s.`WWI City ID` AS city_id,
    s.`City` AS city_name,
    s.`State Province` AS state_province,
    s.`Country` AS country,
    s.`Continent` AS continent,
    s.`Sales Territory` AS sales_territory,
    s.`Region` AS region,
    s.`Subregion` AS subregion,
    s.`Location` AS location,
    s.`Latest Recorded Population` AS latest_population,
    s.`Valid From` AS valid_from,
    s.`Valid To` AS valid_to,
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_city_staging s
  CROSS JOIN max_key mk
  LEFT JOIN _city_lineage l ON TRUE
)
SELECT * FROM existing_closed
UNION ALL
SELECT * FROM new_versions;

-- Mark City lineage row complete (silver copy; bronze land stays as-landed).
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_lineage AS
SELECT
  b.`Lineage Key` AS lineage_key,
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Lineage Key` = l.lineage_key THEN current_timestamp()
    ELSE b.`Data Load Completed`
  END AS data_load_completed,
  CASE
    WHEN b.`Lineage Key` = l.lineage_key THEN TRUE
    ELSE b.`Was Successful`
  END AS was_successful,
  b.`Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage b
LEFT JOIN _city_lineage l ON TRUE;

-- Advance ETL cutoff for City from lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'City' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _city_lineage l ON TRUE;

SELECT 'dim_city_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_city) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_city
        WHERE CAST(valid_to AS DATE) = DATE '9999-12-31') AS current_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.integration_lineage
        WHERE table_name = 'City' AND was_successful IS TRUE) AS lineage_ok_rows;
