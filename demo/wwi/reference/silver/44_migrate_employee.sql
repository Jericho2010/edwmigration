-- Converted from: Integration.MigrateStagedEmployeeData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   silver
-- Patterns:       scd2
-- Notes:          Land-first SCD2 apply: close current dim rows whose WWI id appears in
--                 bronze.integration_employee_staging, then append staging versions with
--                 lineage_key. SQL Server IDENTITY Employee Key → max(existing)+row_number
--                 for new versions only; preserve landed keys. Lineage + ETL cutoff updated
--                 as silver side tables (no federated writes; no multi-table TRAN).

-- Open lineage key for Employee (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _employee_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Employee'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Per-business-key close-off timestamp from staging (MIN Valid From).
CREATE OR REPLACE TEMP VIEW _employee_rows_to_close AS
SELECT
  `WWI Employee ID` AS wwi_employee_id,
  MIN(`Valid From`) AS valid_from
FROM __UC_CATALOG__.bronze.integration_employee_staging
GROUP BY `WWI Employee ID`;

-- Rebuild silver dim: close-off matched current rows, keep others, append staging inserts.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.dim_employee AS
WITH end_of_time AS (
  SELECT CAST('9999-12-31 23:59:59.999999' AS TIMESTAMP) AS ts
),
existing_closed AS (
  SELECT
    d.`Employee Key` AS employee_key,
    d.`WWI Employee ID` AS wwi_employee_id,
    d.`Employee` AS employee_name,
    d.`Preferred Name` AS preferred_name,
    d.`Is Salesperson` AS is_salesperson,
    d.`Photo` AS photo,
    d.`Valid From` AS valid_from,
    CASE
      WHEN rtco.wwi_employee_id IS NOT NULL
           AND (
             d.`Valid To` = e.ts
             OR CAST(d.`Valid To` AS DATE) = DATE '9999-12-31'
           )
        THEN rtco.valid_from
      ELSE d.`Valid To`
    END AS valid_to,
    d.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.dim_employee d
  CROSS JOIN end_of_time e
  LEFT JOIN _employee_rows_to_close rtco
    ON d.`WWI Employee ID` = rtco.wwi_employee_id
),
new_versions AS (
  SELECT
    (
      SELECT COALESCE(MAX(`Employee Key`), 0)
      FROM __UC_CATALOG__.bronze.dim_employee
    ) + ROW_NUMBER() OVER (
      ORDER BY s.`WWI Employee ID`, s.`Valid From`
    ) AS employee_key,
    s.`WWI Employee ID` AS wwi_employee_id,
    s.`Employee` AS employee_name,
    s.`Preferred Name` AS preferred_name,
    s.`Is Salesperson` AS is_salesperson,
    s.`Photo` AS photo,
    s.`Valid From` AS valid_from,
    s.`Valid To` AS valid_to,
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_employee_staging s
  LEFT JOIN _employee_lineage l ON TRUE
)
SELECT * FROM existing_closed
UNION ALL
SELECT * FROM new_versions;

-- Mark Employee lineage row complete (silver copy; bronze land stays as-landed).
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
LEFT JOIN _employee_lineage l ON TRUE;

-- Advance ETL cutoff for Employee from lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Employee' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _employee_lineage l ON TRUE;

SELECT 'dim_employee_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_employee) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_employee
        WHERE CAST(valid_to AS DATE) = DATE '9999-12-31') AS current_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.integration_lineage
        WHERE table_name = 'Employee' AND was_successful IS TRUE) AS lineage_ok_rows;
