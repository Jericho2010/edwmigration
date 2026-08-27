-- 34_metric_daily_sales.sql
-- Metric view over silver.fact_sale for flexible AI/BI / Genie aggregation.
-- Keeps the CTAS mart (30_mart_daily_sales.sql) as a materialized daily grain;
-- this metric view is the semantic layer (AI Dev Kit: databricks-metric-views).

CREATE OR REPLACE VIEW __UC_CATALOG__.gold.metric_daily_sales
WITH METRICS
LANGUAGE YAML
AS $$
  version: 1.1
  source: __UC_CATALOG__.silver.fact_sale
  comment: "Flexible sales KPIs replacing fixed daily CTAS for Genie/AI/BI"
  dimensions:
    - name: Invoice Date
      expr: invoice_date_key
    - name: Stock Item Key
      expr: stock_item_key
    - name: Customer Key
      expr: customer_key
  measures:
    - name: Transaction Count
      expr: COUNT(1)
    - name: Quantity Sold
      expr: SUM(quantity)
    - name: Gross Revenue
      expr: SUM(total_including_tax)
    - name: Profit
      expr: SUM(profit)
$$;

-- Smoke: query via MEASURE()
SELECT
  MEASURE(`Transaction Count`) AS transaction_count,
  MEASURE(`Quantity Sold`) AS quantity_sold,
  MEASURE(`Gross Revenue`) AS gross_revenue
FROM __UC_CATALOG__.gold.metric_daily_sales;
