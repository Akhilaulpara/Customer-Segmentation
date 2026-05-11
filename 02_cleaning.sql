-- ============================================================
--  02_cleaning.sql
--  Purpose : Apply business rules to produce a clean, analysis-
--            ready table from raw_retail.
--  Depends : 01_create_table.sql must have run first.
--  Run     : Second — after loading raw data.
-- ============================================================


-- ---------------------------------------------------------------
-- STEP 1 — UNDERSTAND THE DIRT
--   Run this diagnostic block before anything else.
--   It tells you exactly how many rows each rule will remove.
-- ---------------------------------------------------------------
SELECT
    COUNT(*)                                                    AS total_rows,

    -- Guest checkouts have no customer ID — unusable for RFM
    -- customer_id is VARCHAR in raw_retail; check both NULL and empty string
    SUM(CASE WHEN customer_id IS NULL
              OR customer_id = ''    THEN 1 ELSE 0 END)        AS missing_customer_id,

    -- Negative quantities are product returns / credit notes
    SUM(CASE WHEN quantity <= 0           THEN 1 ELSE 0 END)   AS returns_or_zero_qty,

    -- Zero or negative price = administrative / error rows
    SUM(CASE WHEN unit_price <= 0         THEN 1 ELSE 0 END)   AS zero_or_neg_price,

    -- Invoices starting with 'C' are explicit cancellations
    SUM(CASE WHEN invoice LIKE 'C%'       THEN 1 ELSE 0 END)   AS cancellation_invoices,

    -- Rows that pass ALL filters → what we actually keep
    SUM(CASE
            WHEN (customer_id IS NOT NULL AND customer_id <> '')
             AND quantity     > 0
             AND unit_price   > 0
             AND invoice NOT LIKE 'C%'
            THEN 1 ELSE 0
        END)                                                    AS rows_after_cleaning
FROM raw_retail;


-- ---------------------------------------------------------------
-- STEP 2 — BUILD CLEAN TABLE
--   Rules applied (in order of impact):
--     1. customer_id NOT NULL  → keep only identified customers
--     2. quantity > 0          → exclude returns & credits
--     3. unit_price > 0        → exclude free/error items
--     4. invoice NOT LIKE 'C%' → exclude cancellation orders
--
--   New columns added:
--     line_revenue : quantity × unit_price — the £ value of
--                   each line item, used for Monetary scoring.
-- ---------------------------------------------------------------
DROP TABLE IF EXISTS clean_retail;

CREATE TABLE clean_retail AS
SELECT
    -- customer_id is stored as VARCHAR ("13085.0") in raw_retail
    -- REGEXP_REPLACE strips the ".0" suffix, then we cast to INTEGER
    REGEXP_REPLACE(customer_id, '\.0$', '')::INTEGER  AS customer_id,
    invoice,
    stock_code,
    description,
    invoice_date,
    quantity,
    unit_price,
    ROUND((quantity * unit_price)::NUMERIC, 2)        AS line_revenue,
    country
FROM raw_retail
WHERE
    customer_id IS NOT NULL
    AND customer_id <> ''
    AND quantity    > 0
    AND unit_price  > 0
    AND invoice NOT LIKE 'C%';


-- ---------------------------------------------------------------
-- STEP 3 — POST-CLEAN QUALITY CHECKS
-- ---------------------------------------------------------------

-- Row counts before vs after
SELECT 'raw_retail'   AS source, COUNT(*) AS rows FROM raw_retail
UNION ALL
SELECT 'clean_retail' AS source, COUNT(*) AS rows FROM clean_retail;


-- Confirm no nulls remain in key columns
SELECT
    SUM(CASE WHEN customer_id   IS NULL THEN 1 ELSE 0 END) AS null_customer_id,
    SUM(CASE WHEN invoice        IS NULL THEN 1 ELSE 0 END) AS null_invoice,
    SUM(CASE WHEN invoice_date   IS NULL THEN 1 ELSE 0 END) AS null_invoice_date,
    SUM(CASE WHEN line_revenue  <= 0     THEN 1 ELSE 0 END) AS non_positive_revenue
FROM clean_retail;


-- Customer & order volume in clean data
SELECT
    COUNT(DISTINCT customer_id)   AS unique_customers,
    COUNT(DISTINCT invoice)       AS unique_orders,
    ROUND(SUM(line_revenue), 2)   AS total_revenue_gbp,
    MIN(invoice_date)             AS earliest_date,
    MAX(invoice_date)             AS latest_date
FROM clean_retail;


-- Top 5 countries by revenue (sanity check)
SELECT
    country,
    COUNT(DISTINCT customer_id)   AS customers,
    COUNT(DISTINCT invoice)       AS orders,
    ROUND(SUM(line_revenue), 2)   AS revenue_gbp
FROM clean_retail
GROUP BY country
ORDER BY revenue_gbp DESC
LIMIT 5;