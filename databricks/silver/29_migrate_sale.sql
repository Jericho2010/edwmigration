-- Converted from: Integration.MigrateStagedSaleData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   silver
-- Patterns:       scd_key_lookup, delete_insert, snapshot
-- Notes:          Land-first fact migrate: resolve SCD dimension keys from bronze dims
--                 using Last Modified When in Valid From/To (TOP 1 by Valid From → 0 if
--                 unmatched), drop existing Fact.Sale rows for staged WWI Invoice IDs,
--                 append staging lines with new Sale Key (max landed + row_number) and
--                 open Sale lineage_key. Lineage + ETL cutoff updated as silver side
--                 tables (no federated writes; no multi-table TRAN).

-- Open lineage key for Sale (incomplete load), mirroring TOP 1 ... ORDER BY DESC.
CREATE OR REPLACE TEMP VIEW _sale_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Sale'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- SCD key lookups (point-in-time on Last Modified When); unmatched → 0.
CREATE OR REPLACE TEMP VIEW _sale_city_keys AS
SELECT sale_staging_key, city_key
FROM (
  SELECT
    s.`Sale Staging Key` AS sale_staging_key,
    c.`City Key` AS city_key,
    ROW_NUMBER() OVER (
      PARTITION BY s.`Sale Staging Key`
      ORDER BY c.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_sale_staging s
  INNER JOIN __UC_CATALOG__.bronze.dim_city c
    ON c.`WWI City ID` = s.`WWI City ID`
   AND s.`Last Modified When` > c.`Valid From`
   AND s.`Last Modified When` <= c.`Valid To`
) t
WHERE rn = 1;

CREATE OR REPLACE TEMP VIEW _sale_customer_keys AS
SELECT sale_staging_key, customer_key
FROM (
  SELECT
    s.`Sale Staging Key` AS sale_staging_key,
    c.`Customer Key` AS customer_key,
    ROW_NUMBER() OVER (
      PARTITION BY s.`Sale Staging Key`
      ORDER BY c.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_sale_staging s
  INNER JOIN __UC_CATALOG__.bronze.dim_customer c
    ON c.`WWI Customer ID` = s.`WWI Customer ID`
   AND s.`Last Modified When` > c.`Valid From`
   AND s.`Last Modified When` <= c.`Valid To`
) t
WHERE rn = 1;

CREATE OR REPLACE TEMP VIEW _sale_bill_to_customer_keys AS
SELECT sale_staging_key, bill_to_customer_key
FROM (
  SELECT
    s.`Sale Staging Key` AS sale_staging_key,
    c.`Customer Key` AS bill_to_customer_key,
    ROW_NUMBER() OVER (
      PARTITION BY s.`Sale Staging Key`
      ORDER BY c.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_sale_staging s
  INNER JOIN __UC_CATALOG__.bronze.dim_customer c
    ON c.`WWI Customer ID` = s.`WWI Bill To Customer ID`
   AND s.`Last Modified When` > c.`Valid From`
   AND s.`Last Modified When` <= c.`Valid To`
) t
WHERE rn = 1;

CREATE OR REPLACE TEMP VIEW _sale_stock_item_keys AS
SELECT sale_staging_key, stock_item_key
FROM (
  SELECT
    s.`Sale Staging Key` AS sale_staging_key,
    si.`Stock Item Key` AS stock_item_key,
    ROW_NUMBER() OVER (
      PARTITION BY s.`Sale Staging Key`
      ORDER BY si.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_sale_staging s
  INNER JOIN __UC_CATALOG__.bronze.dim_stock_item si
    ON si.`WWI Stock Item ID` = s.`WWI Stock Item ID`
   AND s.`Last Modified When` > si.`Valid From`
   AND s.`Last Modified When` <= si.`Valid To`
) t
WHERE rn = 1;

CREATE OR REPLACE TEMP VIEW _sale_salesperson_keys AS
SELECT sale_staging_key, salesperson_key
FROM (
  SELECT
    s.`Sale Staging Key` AS sale_staging_key,
    e.`Employee Key` AS salesperson_key,
    ROW_NUMBER() OVER (
      PARTITION BY s.`Sale Staging Key`
      ORDER BY e.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_sale_staging s
  INNER JOIN __UC_CATALOG__.bronze.dim_employee e
    ON e.`WWI Employee ID` = s.`WWI Salesperson ID`
   AND s.`Last Modified When` > e.`Valid From`
   AND s.`Last Modified When` <= e.`Valid To`
) t
WHERE rn = 1;

-- Rebuild fact: retain rows whose invoice is not in staging; append enriched staging.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.fact_sale AS
WITH retained AS (
  SELECT
    f.`Sale Key` AS sale_key,
    f.`City Key` AS city_key,
    f.`Customer Key` AS customer_key,
    f.`Bill To Customer Key` AS bill_to_customer_key,
    f.`Stock Item Key` AS stock_item_key,
    f.`Invoice Date Key` AS invoice_date_key,
    f.`Delivery Date Key` AS delivery_date_key,
    f.`Salesperson Key` AS salesperson_key,
    f.`WWI Invoice ID` AS wwi_invoice_id,
    f.`Description` AS description,
    f.`Package` AS package,
    f.`Quantity` AS quantity,
    f.`Unit Price` AS unit_price,
    f.`Tax Rate` AS tax_rate,
    f.`Total Excluding Tax` AS total_excluding_tax,
    f.`Tax Amount` AS tax_amount,
    f.`Profit` AS profit,
    f.`Total Including Tax` AS total_including_tax,
    f.`Total Dry Items` AS total_dry_items,
    f.`Total Chiller Items` AS total_chiller_items,
    f.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.fact_sale f
  WHERE f.`WWI Invoice ID` NOT IN (
    SELECT DISTINCT `WWI Invoice ID`
    FROM __UC_CATALOG__.bronze.integration_sale_staging
  )
),
incoming AS (
  SELECT
    (
      SELECT COALESCE(MAX(`Sale Key`), 0)
      FROM __UC_CATALOG__.bronze.fact_sale
    ) + ROW_NUMBER() OVER (
      ORDER BY s.`Sale Staging Key`
    ) AS sale_key,
    COALESCE(ck.city_key, 0) AS city_key,
    COALESCE(cuk.customer_key, 0) AS customer_key,
    COALESCE(btk.bill_to_customer_key, 0) AS bill_to_customer_key,
    COALESCE(sik.stock_item_key, 0) AS stock_item_key,
    s.`Invoice Date Key` AS invoice_date_key,
    s.`Delivery Date Key` AS delivery_date_key,
    COALESCE(spk.salesperson_key, 0) AS salesperson_key,
    s.`WWI Invoice ID` AS wwi_invoice_id,
    s.`Description` AS description,
    s.`Package` AS package,
    s.`Quantity` AS quantity,
    s.`Unit Price` AS unit_price,
    s.`Tax Rate` AS tax_rate,
    s.`Total Excluding Tax` AS total_excluding_tax,
    s.`Tax Amount` AS tax_amount,
    s.`Profit` AS profit,
    s.`Total Including Tax` AS total_including_tax,
    s.`Total Dry Items` AS total_dry_items,
    s.`Total Chiller Items` AS total_chiller_items,
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_sale_staging s
  LEFT JOIN _sale_city_keys ck
    ON s.`Sale Staging Key` = ck.sale_staging_key
  LEFT JOIN _sale_customer_keys cuk
    ON s.`Sale Staging Key` = cuk.sale_staging_key
  LEFT JOIN _sale_bill_to_customer_keys btk
    ON s.`Sale Staging Key` = btk.sale_staging_key
  LEFT JOIN _sale_stock_item_keys sik
    ON s.`Sale Staging Key` = sik.sale_staging_key
  LEFT JOIN _sale_salesperson_keys spk
    ON s.`Sale Staging Key` = spk.sale_staging_key
  LEFT JOIN _sale_lineage l ON TRUE
)
SELECT * FROM retained
UNION ALL
SELECT * FROM incoming;

-- Mark Sale lineage row complete (silver copy; bronze land stays as-landed).
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
LEFT JOIN _sale_lineage l ON TRUE;

-- Advance ETL cutoff for Sale from lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.silver.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Sale' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _sale_lineage l ON TRUE;

SELECT 'fact_sale_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.fact_sale) AS rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.silver.integration_lineage
        WHERE table_name = 'Sale' AND was_successful IS TRUE) AS lineage_ok_rows;
