-- Converted from: Integration.MigrateStagedPaymentMethodData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   silver
-- Patterns:       scd2, snapshot
-- Notes:          Land-first SCD2 apply from bronze.integration_paymentmethod_staging onto
--                 bronze.dim_payment_method. Close current versions (Valid To = end-of-time)
--                 whose WWI Payment Method ID appears in staging, then append staging rows
--                 with the open Payment Method lineage_key. IDENTITY Payment Method Key is
--                 synthesized as max(existing)+row_number for new versions only. Lineage
--                 completion and ETL cutoff live on silver copies (Federation is
--                 read-only; BEGIN TRAN is sequential Delta, not multi-table atomic).

-- Open lineage key for Payment Method (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _payment_method_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Payment Method'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Per-business-key close-off timestamp from staging (MIN Valid From).
CREATE OR REPLACE TEMP VIEW _payment_method_rows_to_close AS
SELECT
  `WWI Payment Method ID` AS wwi_payment_method_id,
  MIN(`Valid From`) AS valid_from
FROM __UC_CATALOG__.bronze.integration_paymentmethod_staging
GROUP BY `WWI Payment Method ID`;

-- Rebuild silver dim: close-off matched current rows, keep others, append staging inserts.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.dim_payment_method AS
WITH end_of_time AS (
  SELECT CAST('9999-12-31 23:59:59.999999' AS TIMESTAMP) AS ts
),
existing_closed AS (
  SELECT
    d.`Payment Method Key` AS payment_method_key,
    d.`WWI Payment Method ID` AS payment_method_id,
    d.`Payment Method` AS payment_method,
    d.`Valid From` AS valid_from,
    CASE
      WHEN rtco.wwi_payment_method_id IS NOT NULL
           AND (
             d.`Valid To` = e.ts
             OR CAST(d.`Valid To` AS DATE) = DATE '9999-12-31'
           )
        THEN rtco.valid_from
      ELSE d.`Valid To`
    END AS valid_to,
    d.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.dim_payment_method d
  CROSS JOIN end_of_time e
  LEFT JOIN _payment_method_rows_to_close rtco
    ON d.`WWI Payment Method ID` = rtco.wwi_payment_method_id
),
max_key AS (
  SELECT COALESCE(MAX(payment_method_key), 0) AS max_payment_method_key
  FROM existing_closed
),
new_versions AS (
  SELECT
    CAST(mk.max_payment_method_key + ROW_NUMBER() OVER (
      ORDER BY s.`WWI Payment Method ID`, s.`Valid From`
    ) AS BIGINT) AS payment_method_key,
    s.`WWI Payment Method ID` AS payment_method_id,
    s.`Payment Method` AS payment_method,
    s.`Valid From` AS valid_from,
    s.`Valid To` AS valid_to,
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_paymentmethod_staging s
  CROSS JOIN max_key mk
  LEFT JOIN _payment_method_lineage l ON TRUE
)
SELECT * FROM existing_closed
UNION ALL
SELECT * FROM new_versions;

-- Mark Payment Method lineage row complete (silver copy; bronze land stays as-landed).
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
LEFT JOIN _payment_method_lineage l ON TRUE;

-- Advance ETL cutoff for Payment Method from lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Payment Method' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _payment_method_lineage l ON TRUE;

SELECT 'dim_payment_method_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_payment_method) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_payment_method
        WHERE CAST(valid_to AS DATE) = DATE '9999-12-31') AS current_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.integration_lineage
        WHERE table_name = 'Payment Method' AND was_successful IS TRUE) AS lineage_ok_rows;
