-- ============================================================
--  04_segmentation.sql
--  Purpose : Label each customer into a named business segment
--            based on their RFM scores, then produce the final
--            reporting queries used in presentations / dashboards.
--  Depends : 03_rfm_analysis.sql must have run first.
--  Run     : Last — after RFM scoring.
-- ============================================================


-- ============================================================
--  SEGMENT LOGIC
--
--  Each segment maps to a distinct marketing action.
--  Rules use CASE with ordered WHEN clauses — first match wins.
--
--  ┌──────────────────────┬─────────────────────────────────────────┬──────────────────────────────────┐
--  │ Segment              │ Rule (all conditions must hold)         │ Marketing action                 │
--  ├──────────────────────┼─────────────────────────────────────────┼──────────────────────────────────┤
--  │ Champions            │ R≥4 AND F≥4 AND M≥4                    │ Reward, upsell, brand advocates  │
--  │ Loyal Customers      │ F≥4 AND M≥4 (any recency)              │ Loyalty programme, early access  │
--  │ Potential Loyalists  │ R≥4 AND F in [2,3]                     │ Onboarding series, 2nd purchase  │
--  │ At Risk              │ R≤2 AND F≥3 AND M≥3                    │ Win-back campaign, discount      │
--  │ Lost                 │ R=1 AND F≤2                            │ Sunset or last-chance email      │
--  │ Needs Attention      │ Everything else                         │ Re-engagement, survey            │
--  └──────────────────────┴─────────────────────────────────────────┴──────────────────────────────────┘
--
--  avg_rfm_score = (r_score + f_score + m_score) / 3
--  Used as a continuous health index for ranking customers
--  within a segment (e.g., prioritising the best At-Risk
--  customers for a win-back campaign).
-- ============================================================


-- ---------------------------------------------------------------
-- STEP 1 — BUILD SEGMENT TABLE
-- ---------------------------------------------------------------
DROP TABLE IF EXISTS rfm_segments;

CREATE TABLE rfm_segments AS
SELECT
    customer_id,
    last_purchase_date,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,

    -- Concatenated score string: quick visual fingerprint
    -- e.g. '555' = perfect Champion, '111' = fully lapsed
    CONCAT(r_score, f_score, m_score)               AS rfm_cell,

    -- Composite score: single health metric in [1.0 .. 5.0]
    ROUND((r_score + f_score + m_score) / 3.0, 2)  AS avg_rfm_score,

    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
            THEN 'Champions'
        WHEN f_score >= 4 AND m_score >= 4
            THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score BETWEEN 2 AND 3
            THEN 'Potential Loyalists'
        WHEN r_score <= 2 AND f_score >= 3 AND m_score >= 3
            THEN 'At Risk'
        WHEN r_score = 1 AND f_score <= 2
            THEN 'Lost'
        ELSE
            'Needs Attention'
    END AS segment

FROM rfm_scored;


-- ================================================================
--  REPORTING QUERIES
--  Each query below answers a specific business question.
--  Run them independently after rfm_segments is populated.
-- ================================================================


-- ---------------------------------------------------------------
-- REPORT 1 — EXECUTIVE SEGMENT SUMMARY
--   The headline table for a stakeholder presentation.
--   Shows headcount, revenue share, and average RFM health.
-- ---------------------------------------------------------------
SELECT
    segment,
    COUNT(customer_id)                                        AS customer_count,
    ROUND(
        COUNT(customer_id) * 100.0 / SUM(COUNT(customer_id)) OVER ()
    , 1)                                                      AS pct_of_customers,
    ROUND(AVG(recency_days),  1)                              AS avg_recency_days,
    ROUND(AVG(frequency),     1)                              AS avg_orders,
    ROUND(AVG(monetary),      2)                              AS avg_customer_value_gbp,
    ROUND(SUM(monetary),      2)                              AS total_revenue_gbp,
    ROUND(
        SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER ()
    , 1)                                                      AS pct_of_revenue,
    ROUND(AVG(avg_rfm_score), 2)                              AS avg_rfm_score
FROM rfm_segments
GROUP BY segment
ORDER BY avg_rfm_score DESC;


-- ---------------------------------------------------------------
-- REPORT 2 — CUSTOMER-LEVEL EXPORT
--   One row per customer with all RFM fields.
--   Feed this directly into a CRM or email marketing tool.
-- ---------------------------------------------------------------
SELECT
    customer_id,
    segment,
    rfm_cell,
    avg_rfm_score,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    last_purchase_date
FROM rfm_segments
ORDER BY segment, avg_rfm_score DESC;


-- ---------------------------------------------------------------
-- REPORT 3 — TOP 10 CHAMPIONS BY REVENUE
--   Your most valuable customers — candidates for VIP treatment,
--   referral programmes, or brand ambassador outreach.
-- ---------------------------------------------------------------
SELECT
    customer_id,
    rfm_cell,
    recency_days,
    frequency,
    ROUND(monetary, 2)   AS lifetime_value_gbp,
    last_purchase_date
FROM rfm_segments
WHERE segment = 'Champions'
ORDER BY monetary DESC
LIMIT 10;


-- ---------------------------------------------------------------
-- REPORT 4 — HIGH-VALUE AT-RISK CUSTOMERS
--   These customers used to spend a lot but have gone cold.
--   A targeted win-back campaign should prioritise them by £ value.
-- ---------------------------------------------------------------
SELECT
    customer_id,
    rfm_cell,
    recency_days,
    frequency,
    ROUND(monetary, 2)   AS lifetime_value_gbp,
    last_purchase_date,
    avg_rfm_score
FROM rfm_segments
WHERE segment = 'At Risk'
  AND monetary > 1000             -- only high-value at-risk
ORDER BY monetary DESC;


-- ---------------------------------------------------------------
-- REPORT 5 — POTENTIAL LOYALISTS TO NURTURE
--   Recent first/second-time buyers who haven't yet hit
--   loyal frequency. Target with onboarding series or
--   second-purchase incentive within the next 30 days.
-- ---------------------------------------------------------------
SELECT
    customer_id,
    rfm_cell,
    recency_days,
    frequency,
    ROUND(monetary, 2)   AS revenue_so_far_gbp,
    last_purchase_date
FROM rfm_segments
WHERE segment = 'Potential Loyalists'
ORDER BY recency_days ASC     -- most recent first = highest urgency
LIMIT 50;


-- ---------------------------------------------------------------
-- REPORT 6 — RFM CELL HEATMAP DATA
--   Count and average spend for every R×F combination.
--   Paste into a pivot table / BI tool to build a heatmap.
-- ---------------------------------------------------------------
SELECT
    r_score,
    f_score,
    COUNT(*)                      AS customer_count,
    ROUND(AVG(monetary), 2)       AS avg_monetary,
    ROUND(AVG(avg_rfm_score), 2)  AS avg_health_score
FROM rfm_segments
GROUP BY r_score, f_score
ORDER BY r_score DESC, f_score DESC;


-- ---------------------------------------------------------------
-- REPORT 7 — MONTHLY COHORT REVENUE (BONUS TREND QUERY)
--   Revenue trend across the dataset to provide context for
--   the RFM results — useful for board slides.
-- ---------------------------------------------------------------
SELECT
    DATE_TRUNC('month', invoice_date)  AS month,
    COUNT(DISTINCT customer_id)        AS active_customers,
    COUNT(DISTINCT invoice)            AS total_orders,
    ROUND(SUM(line_revenue), 2)        AS monthly_revenue_gbp
FROM clean_retail
GROUP BY 1
ORDER BY 1;