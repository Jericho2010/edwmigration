-- Converted from: Integration.MigrateStagedTransactionData
-- Source dialect: tsql
-- Classification: migrate
-- Target layer:   gold
-- Patterns:       scd_key_lookup, append_only, lineage
-- Notes:          Land-first append: resolve SCD2 dim keys on bronze
--                 Transaction_Staging via Valid From/To vs Last Modified When
--                 (COALESCE 0 unknown) for Customer, Bill To Customer, Supplier,
--                 Transaction Type, and Payment Method. Append all resolved
--                 staging rows onto bronze fact_transaction with new Transaction
--                 Key (max landed + row_number) and open Transaction lineage_key.
--                 No drop of existing fact rows (source INSERT is append-only).
--                 Staging key UPDATE is inlined (no federated write). Lineage +
--                 ETL cutoff as gold side tables. Multi-table BEGIN TRAN →
--                 sequential Delta (no atomicity).

-- Open lineage key for the in-flight Transaction load (TOP 1 ... ORDER BY DESC).
CREATE OR REPLACE TEMP VIEW _transaction_lineage AS
SELECT
  `Lineage Key` AS lineage_key,
  `Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage
WHERE `Table Name` = 'Transaction'
  AND `Data Load Completed` IS NULL
ORDER BY `Lineage Key` DESC
LIMIT 1;

-- Resolve Customer Key (SCD2 as-of Last Modified When; TOP 1 ORDER BY Valid From).
CREATE OR REPLACE TEMP VIEW _transaction_customer_key AS
SELECT transaction_staging_key, customer_key
FROM (
  SELECT
    t.`Transaction Staging Key` AS transaction_staging_key,
    c.`Customer Key` AS customer_key,
    ROW_NUMBER() OVER (
      PARTITION BY t.`Transaction Staging Key`
      ORDER BY c.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_transaction_staging t
  INNER JOIN __UC_CATALOG__.bronze.dim_customer c
    ON c.`WWI Customer ID` = t.`WWI Customer ID`
   AND t.`Last Modified When` > c.`Valid From`
   AND t.`Last Modified When` <= c.`Valid To`
) x
WHERE rn = 1;

-- Resolve Bill To Customer Key (SCD2; keyed by WWI Bill To Customer ID).
CREATE OR REPLACE TEMP VIEW _transaction_bill_to_customer_key AS
SELECT transaction_staging_key, bill_to_customer_key
FROM (
  SELECT
    t.`Transaction Staging Key` AS transaction_staging_key,
    c.`Customer Key` AS bill_to_customer_key,
    ROW_NUMBER() OVER (
      PARTITION BY t.`Transaction Staging Key`
      ORDER BY c.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_transaction_staging t
  INNER JOIN __UC_CATALOG__.bronze.dim_customer c
    ON c.`WWI Customer ID` = t.`WWI Bill To Customer ID`
   AND t.`Last Modified When` > c.`Valid From`
   AND t.`Last Modified When` <= c.`Valid To`
) x
WHERE rn = 1;

-- Resolve Supplier Key (SCD2 as-of Last Modified When; TOP 1 ORDER BY Valid From).
CREATE OR REPLACE TEMP VIEW _transaction_supplier_key AS
SELECT transaction_staging_key, supplier_key
FROM (
  SELECT
    t.`Transaction Staging Key` AS transaction_staging_key,
    s.`Supplier Key` AS supplier_key,
    ROW_NUMBER() OVER (
      PARTITION BY t.`Transaction Staging Key`
      ORDER BY s.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_transaction_staging t
  INNER JOIN __UC_CATALOG__.bronze.dim_supplier s
    ON s.`WWI Supplier ID` = t.`WWI Supplier ID`
   AND t.`Last Modified When` > s.`Valid From`
   AND t.`Last Modified When` <= s.`Valid To`
) x
WHERE rn = 1;

-- Resolve Transaction Type Key (SCD2 as-of Last Modified When; TOP 1 ORDER BY Valid From).
CREATE OR REPLACE TEMP VIEW _transaction_type_key AS
SELECT transaction_staging_key, transaction_type_key
FROM (
  SELECT
    t.`Transaction Staging Key` AS transaction_staging_key,
    tt.`Transaction Type Key` AS transaction_type_key,
    ROW_NUMBER() OVER (
      PARTITION BY t.`Transaction Staging Key`
      ORDER BY tt.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_transaction_staging t
  INNER JOIN __UC_CATALOG__.bronze.dim_transaction_type tt
    ON tt.`WWI Transaction Type ID` = t.`WWI Transaction Type ID`
   AND t.`Last Modified When` > tt.`Valid From`
   AND t.`Last Modified When` <= tt.`Valid To`
) x
WHERE rn = 1;

-- Resolve Payment Method Key (SCD2 as-of Last Modified When; TOP 1 ORDER BY Valid From).
CREATE OR REPLACE TEMP VIEW _transaction_payment_method_key AS
SELECT transaction_staging_key, payment_method_key
FROM (
  SELECT
    t.`Transaction Staging Key` AS transaction_staging_key,
    pm.`Payment Method Key` AS payment_method_key,
    ROW_NUMBER() OVER (
      PARTITION BY t.`Transaction Staging Key`
      ORDER BY pm.`Valid From`
    ) AS rn
  FROM __UC_CATALOG__.bronze.integration_transaction_staging t
  INNER JOIN __UC_CATALOG__.bronze.dim_payment_method pm
    ON pm.`WWI Payment Method ID` = t.`WWI Payment Method ID`
   AND t.`Last Modified When` > pm.`Valid From`
   AND t.`Last Modified When` <= pm.`Valid To`
) x
WHERE rn = 1;

-- Append-only fact_transaction: keep all bronze rows; append resolved staging
-- (IDENTITY Transaction Key → max landed + row_number).
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.fact_transaction AS
WITH kept AS (
  SELECT
    f.`Transaction Key` AS transaction_key,
    f.`Date Key` AS date_key,
    f.`Customer Key` AS customer_key,
    f.`Bill To Customer Key` AS bill_to_customer_key,
    f.`Supplier Key` AS supplier_key,
    f.`Transaction Type Key` AS transaction_type_key,
    f.`Payment Method Key` AS payment_method_key,
    f.`WWI Customer Transaction ID` AS wwi_customer_transaction_id,
    f.`WWI Supplier Transaction ID` AS wwi_supplier_transaction_id,
    f.`WWI Invoice ID` AS wwi_invoice_id,
    f.`WWI Purchase Order ID` AS wwi_purchase_order_id,
    f.`Supplier Invoice Number` AS supplier_invoice_number,
    f.`Total Excluding Tax` AS total_excluding_tax,
    f.`Tax Amount` AS tax_amount,
    f.`Total Including Tax` AS total_including_tax,
    f.`Outstanding Balance` AS outstanding_balance,
    f.`Is Finalized` AS is_finalized,
    f.`Lineage Key` AS lineage_key
  FROM __UC_CATALOG__.bronze.fact_transaction f
),
staged AS (
  SELECT
    CAST(
      (
        SELECT COALESCE(MAX(`Transaction Key`), 0)
        FROM __UC_CATALOG__.bronze.fact_transaction
      ) + ROW_NUMBER() OVER (
        ORDER BY t.`Transaction Staging Key`
      ) AS BIGINT
    ) AS transaction_key,
    t.`Date Key` AS date_key,
    COALESCE(ck.customer_key, 0) AS customer_key,
    COALESCE(bk.bill_to_customer_key, 0) AS bill_to_customer_key,
    COALESCE(sk.supplier_key, 0) AS supplier_key,
    COALESCE(tk.transaction_type_key, 0) AS transaction_type_key,
    COALESCE(pk.payment_method_key, 0) AS payment_method_key,
    t.`WWI Customer Transaction ID` AS wwi_customer_transaction_id,
    t.`WWI Supplier Transaction ID` AS wwi_supplier_transaction_id,
    t.`WWI Invoice ID` AS wwi_invoice_id,
    t.`WWI Purchase Order ID` AS wwi_purchase_order_id,
    t.`Supplier Invoice Number` AS supplier_invoice_number,
    t.`Total Excluding Tax` AS total_excluding_tax,
    t.`Tax Amount` AS tax_amount,
    t.`Total Including Tax` AS total_including_tax,
    t.`Outstanding Balance` AS outstanding_balance,
    t.`Is Finalized` AS is_finalized,
    l.lineage_key
  FROM __UC_CATALOG__.bronze.integration_transaction_staging t
  LEFT JOIN _transaction_customer_key ck
    ON t.`Transaction Staging Key` = ck.transaction_staging_key
  LEFT JOIN _transaction_bill_to_customer_key bk
    ON t.`Transaction Staging Key` = bk.transaction_staging_key
  LEFT JOIN _transaction_supplier_key sk
    ON t.`Transaction Staging Key` = sk.transaction_staging_key
  LEFT JOIN _transaction_type_key tk
    ON t.`Transaction Staging Key` = tk.transaction_staging_key
  LEFT JOIN _transaction_payment_method_key pk
    ON t.`Transaction Staging Key` = pk.transaction_staging_key
  LEFT JOIN _transaction_lineage l ON TRUE
)
SELECT * FROM kept
UNION ALL
SELECT * FROM staged;

-- Mark Transaction lineage row complete (SYSDATETIME → current_timestamp).
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.integration_lineage AS
SELECT
  b.`Lineage Key` AS lineage_key,
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Lineage Key` = l.lineage_key THEN current_timestamp()
    ELSE b.`Data Load Completed`
  END AS data_load_completed,
  CASE
    WHEN b.`Lineage Key` = l.lineage_key THEN TRUE
    ELSE CAST(b.`Was Successful` AS BOOLEAN)
  END AS was_successful,
  b.`Source System Cutoff Time` AS source_system_cutoff_time
FROM __UC_CATALOG__.bronze.integration_lineage b
LEFT JOIN _transaction_lineage l ON TRUE;

-- Advance ETL cutoff for Transaction to the lineage source-system cutoff.
CREATE OR REPLACE TABLE __UC_CATALOG__.gold.integration_etl_cutoff AS
SELECT
  b.`Table Name` AS table_name,
  CASE
    WHEN b.`Table Name` = 'Transaction' AND l.lineage_key IS NOT NULL
      THEN l.source_system_cutoff_time
    ELSE b.`Cutoff Time`
  END AS cutoff_time
FROM __UC_CATALOG__.bronze.integration_etl_cutoff b
LEFT JOIN _transaction_lineage l ON TRUE;

SELECT 'fact_transaction_ok' AS check_name,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.fact_transaction) AS transaction_rows,
       (SELECT COUNT(*) FROM __UC_CATALOG__.gold.integration_lineage
        WHERE table_name = 'Transaction' AND was_successful IS TRUE) AS transaction_lineage_ok;
