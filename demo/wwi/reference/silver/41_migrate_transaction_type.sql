-- Converted from: Integration.MigrateStagedTransactionTypeData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   silver
-- Patterns:       scd2, snapshot
-- Notes:          Land-first SCD2 apply from bronze.integration_transactiontype_staging onto
--                 bronze.dim_transaction_type. Close current versions (Valid To = end-of-time)
--                 whose WWI Transaction Type ID appears in staging, then append staging rows
--                 with the open Transaction Type lineage_key. IDENTITY Transaction Type Key is
--                 synthesized as max(existing)+row_number for new versions only. Lineage
--                 completion and ETL cutoff live on silver copies (Federation is
--                 read-only; BEGIN TRAN is sequential Delta, not multi-table atomic).

-- Open lineage key for Transaction Type (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _transaction_type_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Transaction Type'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Per-business-key close-off timestamp from staging (MIN Valid From).
CREATE OR REPLACE TEMP VIEW _transaction_type_rows_to_close AS
SELECT
  `WWI Transaction Type ID` AS wwi_transaction_type_id,
  MIN(`Valid From`) AS valid_from
FROM __UC_CATALOG__.bronze.integration_transactiontype_staging
GROUP BY `WWI Transaction Type ID`;

-- Rebuild silver dim: close-off matched current rows, keep others, append staging inserts.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.dim_transaction_type AS
WITH end_of_time AS (
  SELECT CAST('9999-12-31 23:59:59.999999' AS TIMESTAMP) AS ts
),
existing_closed AS (
  SELECT
    d.`Transaction Type Key` AS transaction_type_key,
    d.`WWI Transaction Type ID` AS transaction_type_id,
    d.`Transaction Type` AS transaction_type,
    d.`Valid From` AS valid_from,
    CASE
      WHEN rtco.wwi_transaction_type_id IS NOT NULL
           AND (
             d.`Valid To` = e.ts
             OR CAST(d.`Valid To` AS DATE) = DATE '9999-12-31'
           )
        THEN rtco.valid_from
      ELSE d.`Valid To`
    END AS valid_to,
    d.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.dim_transaction_type d
  CROSS JOIN end_of_time e
  LEFT JOIN _transaction_type_rows_to_close rtco
    ON d.`WWI Transaction Type ID` = rtco.wwi_transaction_type_id
),
max_key AS (
  SELECT COALESCE(MAX(transaction_type_key), 0) AS max_transaction_type_key
  FROM existing_closed
),
new_versions AS (
  SELECT
    CAST(mk.max_transaction_type_key + ROW_NUMBER() OVER (
      ORDER BY s.`WWI Transaction Type ID`, s.`Valid From`
    ) AS BIGINT) AS transaction_type_key,
    s.`WWI Transaction Type ID` AS transaction_type_id,
    s.`Transaction Type` AS transaction_type,
    s.`Valid From` AS valid_from,
    s.`Valid To` AS valid_to,
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_transactiontype_staging s
  CROSS JOIN max_key mk
  LEFT JOIN _transaction_type_lineage l ON TRUE
)
SELECT * FROM existing_closed
UNION ALL
SELECT * FROM new_versions;

-- Mark Transaction Type lineage row complete (silver copy; bronze land stays as-landed).
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
LEFT JOIN _transaction_type_lineage l ON TRUE;

-- Advance ETL cutoff for Transaction Type from lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Transaction Type' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _transaction_type_lineage l ON TRUE;

SELECT 'dim_transaction_type_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_transaction_type) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_transaction_type
        WHERE CAST(valid_to AS DATE) = DATE '9999-12-31') AS current_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.integration_lineage
        WHERE table_name = 'Transaction Type' AND was_successful IS TRUE) AS lineage_ok_rows;
