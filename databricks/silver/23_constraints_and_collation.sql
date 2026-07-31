-- 23_constraints_and_collation.sql
-- Dimensional PK/FK (NOT ENFORCED) + case-insensitive name collations.
-- AI Dev Kit databricks-dbsql guidance: define PK/FK for dimensional models;
-- use COLLATE UTF8_LCASE on user-facing string columns.

-- Preserve existing tables; add constraints where supported.
ALTER TABLE edw_migration.silver.dim_city
  ADD CONSTRAINT dim_city_pk PRIMARY KEY (city_key) NOT ENFORCED;

ALTER TABLE edw_migration.silver.dim_stock_item
  ADD CONSTRAINT dim_stock_item_pk PRIMARY KEY (stock_item_key) NOT ENFORCED;

ALTER TABLE edw_migration.silver.dim_customer_scd2
  ADD CONSTRAINT dim_customer_scd2_pk PRIMARY KEY (customer_key) NOT ENFORCED;

ALTER TABLE edw_migration.silver.dim_date
  ADD CONSTRAINT dim_date_pk PRIMARY KEY (date_key) NOT ENFORCED;

ALTER TABLE edw_migration.silver.fact_sale
  ADD CONSTRAINT fact_sale_pk PRIMARY KEY (sale_key) NOT ENFORCED;

ALTER TABLE edw_migration.silver.fact_sale
  ADD CONSTRAINT fact_sale_fk_customer FOREIGN KEY (customer_key)
  REFERENCES edw_migration.silver.dim_customer_scd2 (customer_key) NOT ENFORCED;

ALTER TABLE edw_migration.silver.fact_sale
  ADD CONSTRAINT fact_sale_fk_stock FOREIGN KEY (stock_item_key)
  REFERENCES edw_migration.silver.dim_stock_item (stock_item_key) NOT ENFORCED;

-- Case-insensitive display names (recreate gold marts with COLLATE where practical).
-- Applied on gold customer/city name columns via views for Genie/search demos.
CREATE OR REPLACE VIEW edw_migration.gold.v_mart_customer_current_ci AS
SELECT
  customer_key,
  customer_id,
  customer_name COLLATE UTF8_LCASE AS customer_name,
  bill_to_customer_id,
  category,
  buying_group_id,
  city_id,
  city_name COLLATE UTF8_LCASE AS city_name,
  state_province,
  country
FROM edw_migration.gold.mart_customer_current;

CREATE OR REPLACE VIEW edw_migration.gold.v_mart_city_dimension_ci AS
SELECT
  city_key,
  city_id,
  city_name COLLATE UTF8_LCASE AS city_name,
  state_province,
  country,
  latest_population,
  valid_from,
  valid_to
FROM edw_migration.gold.mart_city_dimension;

SELECT 'constraints_and_collation_ok' AS check_name;
