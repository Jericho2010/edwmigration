-- Converted from: Integration.MigrateStagedSupplierData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   silver
-- Patterns:       scd2, snapshot
-- Notes:          Land-first SCD2 apply from bronze.integration_supplier_staging onto
--                 bronze.dim_supplier. Close current versions (Valid To = end-of-time)
--                 whose WWI Supplier ID appears in staging, then append staging rows
--                 with the open Supplier lineage_key. IDENTITY Supplier Key is synthesized
--                 as max(existing)+row_number for new versions only. Lineage
--                 completion and ETL cutoff live on silver copies (Federation is
--                 read-only; BEGIN TRAN is sequential Delta, not multi-table atomic).

-- Open lineage key for Supplier (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _supplier_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Supplier'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Per-business-key close-off timestamp from staging (MIN Valid From).
CREATE OR REPLACE TEMP VIEW _supplier_rows_to_close AS
SELECT
  `WWI Supplier ID` AS wwi_supplier_id,
  MIN(`Valid From`) AS valid_from
FROM __UC_CATALOG__.bronze.integration_supplier_staging
GROUP BY `WWI Supplier ID`;

-- Rebuild silver dim: close-off matched current rows, keep others, append staging inserts.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.dim_supplier AS
WITH end_of_time AS (
  SELECT CAST('9999-12-31 23:59:59.999999' AS TIMESTAMP) AS ts
),
existing_closed AS (
  SELECT
    d.`Supplier Key` AS supplier_key,
    d.`WWI Supplier ID` AS supplier_id,
    d.`Supplier` AS supplier_name,
    d.`Category` AS category,
    d.`Primary Contact` AS primary_contact,
    d.`Supplier Reference` AS supplier_reference,
    d.`Payment Days` AS payment_days,
    d.`Postal Code` AS postal_code,
    d.`Valid From` AS valid_from,
    CASE
      WHEN rtco.wwi_supplier_id IS NOT NULL
           AND (
             d.`Valid To` = e.ts
             OR CAST(d.`Valid To` AS DATE) = DATE '9999-12-31'
           )
        THEN rtco.valid_from
      ELSE d.`Valid To`
    END AS valid_to,
    d.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.dim_supplier d
  CROSS JOIN end_of_time e
  LEFT JOIN _supplier_rows_to_close rtco
    ON d.`WWI Supplier ID` = rtco.wwi_supplier_id
),
max_key AS (
  SELECT COALESCE(MAX(supplier_key), 0) AS max_supplier_key
  FROM existing_closed
),
new_versions AS (
  SELECT
    CAST(mk.max_supplier_key + ROW_NUMBER() OVER (
      ORDER BY s.`WWI Supplier ID`, s.`Valid From`
    ) AS BIGINT) AS supplier_key,
    s.`WWI Supplier ID` AS supplier_id,
    s.`Supplier` AS supplier_name,
    s.`Category` AS category,
    s.`Primary Contact` AS primary_contact,
    s.`Supplier Reference` AS supplier_reference,
    s.`Payment Days` AS payment_days,
    s.`Postal Code` AS postal_code,
    s.`Valid From` AS valid_from,
    s.`Valid To` AS valid_to,
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_supplier_staging s
  CROSS JOIN max_key mk
  LEFT JOIN _supplier_lineage l ON TRUE
)
SELECT * FROM existing_closed
UNION ALL
SELECT * FROM new_versions;

-- Mark Supplier lineage row complete (silver copy; bronze land stays as-landed).
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
LEFT JOIN _supplier_lineage l ON TRUE;

-- Advance ETL cutoff for Supplier from lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Supplier' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _supplier_lineage l ON TRUE;

SELECT 'dim_supplier_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_supplier) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.dim_supplier
        WHERE CAST(valid_to AS DATE) = DATE '9999-12-31') AS current_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.integration_lineage
        WHERE table_name = 'Supplier' AND was_successful IS TRUE) AS lineage_ok_rows;
