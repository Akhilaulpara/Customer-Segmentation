-- ============================================================
--  03_rfm_analysis.sql
--  Purpose : Compute raw RFM metrics and score each customer
--            into 5 quantile buckets using NTILE().
--  Engine  : PostgreSQL 13+
--  Depends : 02_cleaning.sql must have run first.
--  Run     : Third — after cleaning.
-- ============================================================


-- ============================================================
--  WHAT IS RFM?
--
--  R — RECENCY   : days since the customer's last purchase.
--                  Lower = more recent = better.
--  F — FREQUENCY : count of distinct orders placed.
--                  Higher = more loyal = better.
--  M — MONETARY  : total £ revenue generated lifetime.
--                  Higher = more valuable = better.
--
--  Reference date = MAX(invoice_date) + 1 day
--  We anchor to the last transaction in the dataset rather than
--  CURRENT_DATE so scores stay consistent whenever the query
--  re-runs. The +1 day means the most recent buyer gets
--  recency_days = 1 (not 0), which avoids edge cases.
-- ============================================================


-- ---------------------------------------------------------------
-- STEP 1 — ORDER-LEVEL AGGREGATION
--   Collapse line items → one row per invoice.
--   Without this step a 12-item basket counts as 12 "purchases",
--   which would artificially inflate the Frequency score.
-- ---------------------------------------------------------------
DROP TABLE IF EXISTS order_summary;

CREATE TABLE order_summary AS
SELECT
    customer_id,
    invoice,
    invoice_date,
    SUM(line_revenue)  AS order_value
FROM clean_retail
GROUP BY customer_id, invoice, invoice_date;


-- Sanity check: row count and distinct invoice count must match
SELECT
    COUNT(*)                 AS total_order_rows,
    COUNT(DISTINCT invoice)  AS distinct_invoices   -- both should be equal
FROM order_summary;


-- ---------------------------------------------------------------
-- STEP 2 — RAW RFM METRICS PER CUSTOMER
-- ---------------------------------------------------------------
DROP TABLE IF EXISTS rfm_raw;

CREATE TABLE rfm_raw AS

WITH reference AS (
    -- Compute once and reuse for all recency calculations
    SELECT MAX(invoice_date) + INTERVAL '1 day' AS ref_date
    FROM order_summary
)

SELECT
    o.customer_id,

    MAX(o.invoice_date)                                              AS last_purchase_date,

    -- RECENCY: days between last purchase and the reference date
    -- PostgreSQL: cast the interval result to integer days
    EXTRACT(EPOCH FROM (r.ref_date - MAX(o.invoice_date)))::INTEGER / 86400
                                                                     AS recency_days,

    COUNT(DISTINCT o.invoice)                                        AS frequency,

    ROUND(SUM(o.order_value)::NUMERIC, 2)                           AS monetary

FROM order_summary  o
CROSS JOIN reference r
GROUP BY o.customer_id, r.ref_date;


-- Quick distribution check on raw values before scoring
SELECT
    MIN(recency_days)                                                 AS min_recency,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY recency_days)) AS median_recency,
    MAX(recency_days)                                                 AS max_recency,

    MIN(frequency)                                                    AS min_freq,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY frequency))    AS median_freq,
    MAX(frequency)                                                    AS max_freq,

    MIN(monetary)                                                     AS min_monetary,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monetary))     AS median_monetary,
    MAX(monetary)                                                     AS max_monetary
FROM rfm_raw;


-- ---------------------------------------------------------------
-- STEP 3 — RFM SCORES USING NTILE(5)
--
--  NTILE(5) divides the sorted result into 5 equal-sized buckets
--  and assigns each row a bucket number 1..5.
--
--  Scoring direction (5 = best on every dimension):
--    R: ORDER BY recency_days DESC  → bucket 5 = fewest days ago
--    F: ORDER BY frequency ASC      → bucket 5 = most orders
--    M: ORDER BY monetary ASC       → bucket 5 = highest spend
-- ---------------------------------------------------------------
DROP TABLE IF EXISTS rfm_scored;

CREATE TABLE rfm_scored AS
SELECT
    customer_id,
    last_purchase_date,
    recency_days,
    frequency,
    monetary,

    NTILE(5) OVER (ORDER BY recency_days DESC)  AS r_score,
    NTILE(5) OVER (ORDER BY frequency    ASC)   AS f_score,
    NTILE(5) OVER (ORDER BY monetary     ASC)   AS m_score
FROM rfm_raw;


-- ---------------------------------------------------------------
-- STEP 4 — SCORE DISTRIBUTION VALIDATION
-- Each bucket should contain ~20% of customers.
-- ---------------------------------------------------------------
SELECT
    'R' AS dimension,  r_score AS score,  COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct
FROM rfm_scored
GROUP BY r_score

UNION ALL

SELECT
    'F', f_score, COUNT(*),
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)
FROM rfm_scored
GROUP BY f_score

UNION ALL

SELECT
    'M', m_score, COUNT(*),
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)
FROM rfm_scored
GROUP BY m_score

ORDER BY dimension, score;


-- Validate scoring direction:
-- avg_recency should DECREASE as r_score increases (5 = most recent)
-- avg_frequency should INCREASE as f_score increases
-- avg_monetary  should INCREASE as m_score increases
SELECT
    r_score,
    ROUND(AVG(recency_days), 1)  AS avg_recency_days,
    f_score,
    ROUND(AVG(frequency), 1)     AS avg_frequency,
    m_score,
    ROUND(AVG(monetary), 2)      AS avg_monetary
FROM rfm_scored
GROUP BY r_score, f_score, m_score
ORDER BY r_score DESC, f_score DESC, m_score DESC
LIMIT 15;


-- Top 20 customers by composite RFM score
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    r_score + f_score + m_score  AS composite_score
FROM rfm_scored
ORDER BY composite_score DESC, monetary DESC
LIMIT 20;