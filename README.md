# RFM Customer Segmentation — SQL Project

> **Resume line:** "Built an RFM segmentation model in SQL using NTILE() and chained CTEs, categorizing 5,878 customers across 6 behavioural segments to identify a Champion cohort generating 68% of £17.7M in total revenue — informing a targeted re-engagement strategy."

---

## Project overview

A D2C brand sitting on two years of transaction history needs to answer a simple question: **who are our best customers, who is slipping away, and who is already gone?**

This project answers that question entirely in SQL, using the **RFM framework** — a proven marketing-science technique that scores every customer on three dimensions derived from their purchase history:

| Dimension | Question answered | Direction |
|-----------|------------------|-----------|
| **R** ecency | How long ago did they last buy? | Lower days = better |
| **F** requency | How many orders have they placed? | Higher = better |
| **M** onetary | How much have they spent in total? | Higher = better |

Each dimension is scored 1–5 using `NTILE(5)`. The three scores are combined to assign every customer to one of six named segments, each with a clear marketing action.
<img width="1878" height="999" alt="Image" src="https://github.com/user-attachments/assets/e19a7972-1dad-4963-9526-0ada439c8de1" />
---

## Dataset

**Online Retail II** — UCI Machine Learning Repository / Kaggle  
UK-based online gift retailer, December 2009 – December 2011

| Field | Type | Description |
|-------|------|-------------|
| `Invoice` | VARCHAR | Invoice number (`C` prefix = cancellation) |
| `StockCode` | VARCHAR | Product code |
| `Description` | VARCHAR | Product name |
| `Quantity` | INTEGER | Units per line item (negative = return) |
| `InvoiceDate` | TIMESTAMP | Transaction timestamp |
| `Price` | DECIMAL | Unit price in GBP |
| `Customer ID` | INTEGER | Unique customer identifier (nullable = guest) |
| `Country` | VARCHAR | Customer country |

---

## Project structure

```
rfm-sql-project/
│
├── data/
│   └── online_retail.csv          ← raw dataset (place file here)
│
├── sql/
│   ├── 01_create_table.sql        ← schema definition + CSV load
│   ├── 02_cleaning.sql            ← data quality rules + clean table
│   ├── 03_rfm_analysis.sql        ← RFM metrics + NTILE scoring
│   └── 04_segmentation.sql        ← segment labels + 7 reports
│
└── README.md
```

---

## How to run 

### Option A — DuckDB CLI (recommended, zero setup)

```bash
# Install DuckDB (one-time)
pip install duckdb

# Launch interactive shell from project root
duckdb

# Run scripts in order
.read sql/01_create_table.sql
.read sql/02_cleaning.sql
.read sql/03_rfm_analysis.sql
.read sql/04_segmentation.sql
```

### Option B — Python + DuckDB

```python
import duckdb

con = duckdb.connect()

for script in [
    "sql/01_create_table.sql",
    "sql/02_cleaning.sql",
    "sql/03_rfm_analysis.sql",
    "sql/04_segmentation.sql",
]:
    con.execute(open(script).read())

# Pull the executive summary
df = con.execute("""
    SELECT segment, customer_count, pct_of_revenue, avg_rfm_score
    FROM (
        SELECT segment,
               COUNT(*) AS customer_count,
               ROUND(SUM(monetary)*100.0/SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue,
               ROUND(AVG(avg_rfm_score), 2) AS avg_rfm_score
        FROM rfm_segments
        GROUP BY segment
    )
    ORDER BY avg_rfm_score DESC
""").fetchdf()

print(df)
```

### Option C — PostgreSQL adaptation

The only changes needed for PostgreSQL:

| DuckDB syntax | PostgreSQL equivalent |
|---|---|
| `read_csv_auto(...)` | `COPY raw_retail FROM '...' CSV HEADER;` |
| `DATE_DIFF('day', a, b)` | `b::date - a::date` |
| `INTERVAL 1 DAY` | `INTERVAL '1 day'` |
| `CONCAT(a, b, c)` | `a::text \|\| b::text \|\| c::text` |

---

## SQL concepts showcased

| Concept | Where used | Why it matters |
|---------|-----------|----------------|
| `NTILE(n) OVER (ORDER BY ...)` | `03_rfm_analysis.sql` | Percentile bucketing without thresholds — adapts to any customer distribution |
| `COUNT(DISTINCT ...)` | `03_rfm_analysis.sql` | Correctly counts orders regardless of how many line items each has |
| `DATE_DIFF()` | `03_rfm_analysis.sql` | Anchors recency to the dataset's last date, making scores reproducible |
| `SUM(...) OVER ()` | `04_segmentation.sql` | Window function for revenue share % without a self-join |
| `CASE WHEN` ordered matching | `04_segmentation.sql` | First-match CASE ensures mutually exclusive segment assignment |
| Multi-step `CREATE TABLE AS` | All files | Materialises intermediate results — makes each step auditable |
| CTEs + subqueries | Throughout | Readable, step-by-step logic that non-SQL readers can follow |

---

## Results

### Segment summary

| Segment | Customers | % of base | Avg recency | Avg orders | Avg value £ | Revenue % |
|---------|-----------|-----------|-------------|------------|-------------|-----------|
| Champions | 1,299 | 22.1% | 21 days | 17.1 | £9,327 | **68.5%** |
| Loyal Customers | 635 | 10.8% | 182 days | 9.3 | £4,211 | 15.1% |
| Potential Loyalists | 693 | 11.8% | 23 days | 2.6 | £1,136 | 4.5% |
| Needs Attention | 1,974 | 33.6% | 194 days | 2.4 | £632 | 7.1% |
| At Risk | 395 | 6.7% | 375 days | 3.7 | £1,378 | 3.1% |
| Lost | 882 | 15.0% | 565 days | 1.2 | £424 | 2.1% |
| **Total** | **5,878** | 100% | — | — | — | **100%** |

### Key findings

- **Champions (22% of customers) drive 68.5% of revenue.** Protecting this segment is the single highest-ROI activity. Reward programmes and early access initiatives should target this group first.
- **395 At-Risk customers generated £544K but are going cold** (avg 375 days since last purchase). A win-back campaign targeting those with `monetary > £1,000` could recover significant revenue at low cost.
- **693 Potential Loyalists bought recently but only once or twice.** A 30-day onboarding email sequence or second-purchase incentive is the highest-leverage conversion play.
- **882 Lost customers (15% of base) are likely unrecoverable** — average last purchase was 565 days ago. Consider sunsetting from active campaigns to reduce list cost.
<img width="1759" height="888" alt="Image" src="https://github.com/user-attachments/assets/550abd5f-a61c-44ea-bd57-138dd5804dac" />
<img width="1920" height="1080" alt="Image" src="https://github.com/user-attachments/assets/d4cf8d95-6304-4476-b2ce-97d94df7474e" />
---

## Segment marketing playbook

| Segment | Priority | Recommended action |
|---------|----------|--------------------|
| Champions | High | VIP rewards, referral programme, exclusive previews |
| Loyal Customers | High | Loyalty points, birthday offers, subscription nudge |
| Potential Loyalists | Medium | Welcome series, 2nd-purchase discount (10–15%) |
| At Risk | Medium | "We miss you" win-back, time-limited offer |
| Needs Attention | Low | Re-engagement survey, product recommendation email |
| Lost | Very low | Sunset sequence or final reactivation attempt |

---

## Extending the project

- **Add a country filter** in `02_cleaning.sql` to segment UK vs. international customers separately
- **Run quarterly snapshots** by adding a `snapshot_date` column — enables cohort migration analysis ("how many At-Risk customers became Champions after the win-back campaign?")
- **Join to a product table** to see which categories Champions buy vs. Lost customers — informs assortment strategy
- **Export `04_segmentation.sql` Report 2** to a CSV and load into Mailchimp / HubSpot for direct campaign execution
