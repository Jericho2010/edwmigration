-- Converted from: Integration.MigrateStagedEmployeeData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   silver
-- Patterns:       scd2
-- Notes:          SCD2 close-and-insert from bronze employee staging onto landed
--                 dim_employee. Open Integration.Lineage row for Employee is marked
--                 complete; Integration.ETL Cutoff Cutoff Time advances to the
--                 lineage Source System Cutoff Time. Multi-table BEGIN TRAN is
--                 expressed as sequential Delta statements (no cross-table atomicity).

-- Open lineage key for the in-flight Employee load (TOP 1 ... ORDER BY DESC).
CREATE OR REPLACE TEMP VIEW _employee_lineage_key AS
SELECT `Lineage Key` AS lineage_key
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Employee'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Min Valid From per business key in staging → close-off boundary for current rows.
CREATE OR REPLACE TEMP VIEW _employee_rows_to_close AS
SELECT
  `WWI Employee ID` AS wwi_employee_id,
  MIN(`Valid From`) AS valid_from
FROM __UC_CATALOG__.bronze.integration_employee_staging
GROUP BY `WWI Employee ID`;

-- End-of-time sentinel used by the legacy proc.
-- TIMESTAMP '9999-12-31 23:59:59.9999999'

-- Apply SCD2: close current versions, then append staging rows with lineage_key.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.dim_employee AS
WITH closed AS (
  SELECT
    e.`Employee Key` AS employee_key,
    e.`WWI Employee ID` AS wwi_employee_id,
    e.`Employee` AS employee_name,
    e.`Preferred Name` AS preferred_name,
    e.`Is Salesperson` AS is_salesperson,
    e.`Photo` AS photo,
    e.`Valid From` AS valid_from,
    CASE
      WHEN rtco.wwi_employee_id IS NOT NULL
           AND e.`Valid To` = TIMESTAMP '9999-12-31 23:59:59.9999999'
        THEN rtco.valid_from
      ELSE e.`Valid To`
    END AS valid_to,
    e.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.dim_employee e
  LEFT JOIN _employee_rows_to_close rtco
    ON e.`WWI Employee ID` = rtco.wwi_employee_id
),
max_key AS (
  SELECT COALESCE(MAX(employee_key), 0) AS max_employee_key
  FROM closed
),
staged AS (
  SELECT
    CAST(mk.max_employee_key + ROW_NUMBER() OVER (
      ORDER BY s.`WWI Employee ID`, s.`Valid From`
    ) AS BIGINT) AS employee_key,
    s.`WWI Employee ID` AS wwi_employee_id,
    s.`Employee` AS employee_name,
    s.`Preferred Name` AS preferred_name,
    s.`Is Salesperson` AS is_salesperson,
    s.`Photo` AS photo,
    s.`Valid From` AS valid_from,
    s.`Valid To` AS valid_to,
    lk.lineage_key
  FROM __UC_CATALOG__.bronze.integration_employee_staging s
  CROSS JOIN _employee_lineage_key lk
  CROSS JOIN max_key mk
)
SELECT * FROM closed
UNION ALL
SELECT * FROM staged;

-- Mark Employee lineage row complete (SYSDATETIME → current_timestamp).
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_lineage AS
SELECT
  l.`Lineage Key` AS lineage_key,
  l.`Table Name` AS table_name,
  l.`Source System Cutoff Time` AS source_system_cutoff_time,
  CASE
    WHEN l.`Lineage Key` = (SELECT lineage_key FROM _employee_lineage_key)
         AND l.`Table Name` = 'Employee'
         AND l.`Data Load Completed` IS NULL
      THEN current_timestamp()
    ELSE l.`Data Load Completed`
  END AS data_load_completed,
  CASE
    WHEN l.`Lineage Key` = (SELECT lineage_key FROM _employee_lineage_key)
         AND l.`Table Name` = 'Employee'
         AND l.`Data Load Completed` IS NULL
      THEN true
    ELSE CAST(l.`Was Successful` AS BOOLEAN)
  END AS was_successful
FROM __UC_CATALOG__.bronze.integration_lineage l;

-- Advance ETL cutoff for Employee to the lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_etl_cutoff AS
SELECT
  c.`Table Name` AS table_name,
  CASE
    WHEN c.`Table Name` = 'Employee'
      THEN COALESCE(
        (
          SELECT l.source_system_cutoff_time
          FROM __UC_CATALOG__.silver.integration_lineage l
          WHERE l.lineage_key = (SELECT lineage_key FROM _employee_lineage_key)
        ),
        c.`Cutoff Time`
      )
    ELSE c.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff c;

SELECT 'dim_employee_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_employee) AS employee_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_employee
        WHERE valid_to = TIMESTAMP '9999-12-31 23:59:59.9999999') AS current_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.integration_lineage
        WHERE table_name = 'Employee' AND was_successful = true) AS employee_lineage_ok;
