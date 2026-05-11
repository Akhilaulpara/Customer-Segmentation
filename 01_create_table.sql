-- ============================================================
--  01_create_table.sql
--  Purpose : Define schema and load raw data into PostgreSQL.
--  Engine  : PostgreSQL 13+
--  Run     : First — before any other script.
--
--  HOW TO LOAD THE CSV (two options):
--
--  Option A — psql command line (recommended):
--    \copy raw_retail FROM 'data/online_retail_II.csv'
--    WITH (FORMAT csv, HEADER true, NULL '');
--
--  Option B — superuser server-side COPY:
--    COPY raw_retail FROM '/absolute/path/online_retail_II.csv'
--    WITH (FORMAT csv, HEADER true, NULL '');
--
--  NOTE: Customer ID arrives as a float-like string ("13085.0")
--  in the CSV because Excel/pandas writes nullable integers
--  as doubles. We store it as VARCHAR here and cast it to
--  INTEGER in 02_cleaning.sql after stripping the ".0".
-- ============================================================


DROP TABLE IF EXISTS raw_retail;

CREATE TABLE raw_retail (
    invoice      VARCHAR,        -- 'C' prefix = cancellation; 'A' = bad-debt adj
    stock_code   VARCHAR,        -- purely-alpha = internal charge code (POST, DOT, M …)
    description  VARCHAR,        -- nullable: ~4 382 rows have no description
    quantity     INTEGER,        -- negative on returns / cancellations
    invoice_date TIMESTAMP,      -- transaction timestamp (no timezone in source)
    unit_price   NUMERIC(10, 4), -- GBP per unit; 0 = sample/admin line
    customer_id  VARCHAR,        -- stored as VARCHAR to handle "13085.0" from CSV
    country      VARCHAR
);


-- ---------------------------------------------------------------
-- LOAD THE CSV
-- Run this in psql after the CREATE TABLE above:
--
--   \copy raw_retail FROM 'data/online_retail_II.csv'
--   WITH (FORMAT csv, HEADER true, NULL '');
--
-- The \copy command (backslash) runs client-side and works for
-- any psql user. COPY (no backslash) is server-side and requires
-- superuser privilege plus an absolute path the server can read.
-- ---------------------------------------------------------------


-- ---------------------------------------------------------------
-- POST-LOAD AUDIT
-- Run immediately after \copy to confirm the data loaded correctly.
-- Expected values are in the comments on each line.
-- ---------------------------------------------------------------
SELECT
    COUNT(*)                                                 AS total_rows,          -- 1 067 371
    COUNT(*)        FILTER (WHERE customer_id IS NOT NULL
                        AND customer_id <> '')               AS rows_with_customer,  --   824 364
    COUNT(*)        FILTER (WHERE customer_id IS NULL
                         OR customer_id = '')                AS guest_rows,          --   243 007
    COUNT(DISTINCT invoice)                                  AS unique_invoices,     --    37 897
    COUNT(*)        FILTER (WHERE invoice LIKE 'C%')         AS cancellation_rows,   --    19 494
    COUNT(*)        FILTER (WHERE invoice LIKE 'A%')         AS bad_debt_rows,       --         6
    COUNT(*)        FILTER (WHERE quantity < 0)              AS negative_qty_rows,   --    22 950
    COUNT(*)        FILTER (WHERE unit_price = 0)            AS zero_price_rows,     --     6 202
    COUNT(*)        FILTER (WHERE description IS NULL)       AS null_desc_rows,      --     4 382
    MIN(invoice_date)                                        AS earliest_date,
    MAX(invoice_date)                                        AS latest_date
FROM raw_retail;