# Olist E-Commerce Analytics

---

## Project Summary

An end-to-end data analytics project on the **Brazilian E-Commerce Public Dataset by Olist** covering 99,441 orders, 95,420 customers, and 3,095 sellers between September 2016 and October 2018.

The project takes raw CSV files through a complete analytical pipeline — staging, validation, transformation, analytical SQL in **MySQL**, and a 5-page executive dashboard in **Power BI** — and delivers a focused set of business recommendations rather than descriptive charts. The central finding: late delivery is the strongest driver of poor customer reviews, and the problem is concentrated in a small, addressable group of high-revenue sellers and specific geographies.

---

## Overview

Olist is a Brazilian e-commerce marketplace connecting small and medium sellers to customers across all 27 states. Management wanted to understand why growth plateaued in 2018 and where to focus to improve customer experience without sacrificing revenue.

This project answers three questions:

1. Where is revenue coming from, and is growth sustainable?
2. What drives poor customer reviews?
3. Which sellers should Olist prioritize for intervention?

The analysis was built from raw data through to executive visualization, with each layer validated before the next was built.

---

## Problem Statement

Olist's marketplace experienced rapid growth during 2017 but reached a plateau of approximately R$1 million in monthly order value by mid-2018. Management needed to know:

- Whether the plateau reflects market saturation, a retention problem, or an operational issue
- What operational factors are actually driving poor customer reviews
- Which sellers, regions, or categories deserve priority intervention to protect revenue and customer trust

The goal was to move from descriptive reporting to **decision support** — identifying specific, quantified intervention targets.

---

## Dataset

**Source:** [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

**Volume:**

| Table | Rows | Grain |
|---|---|---|
| `olist_customers` | 99,441 | One row per customer_id |
| `olist_orders` | 99,441 | One row per order |
| `olist_order_items` | 112,650 | One row per item within an order |
| `olist_order_payments` | 103,886 | One row per payment sequence |
| `olist_order_reviews` | 99,223 | One row per review |
| `olist_products` | 32,951 | One row per product |
| `olist_sellers` | 3,095 | One row per seller |
| `olist_geolocation` | ~1M | One row per coordinate |
| `product_category_name_translation` | 71 | One row per category |

**Period:** September 2016 – October 2018

**Domain:** E-commerce marketplace — orders, customers, products, sellers, payments, reviews, freight, geography

---

## Tools and Technologies

| Layer | Tool | Purpose |
|---|---|---|
| Data storage | MySQL | Staging, validation, transformation, analytical queries |
| Data ingestion | MySQL `LOAD DATA LOCAL INFILE` | Raw CSV loading |
| Analytical SQL | MySQL (CTEs, window functions) | Business analysis, KPI computation |
| Visualization | Power BI Desktop | Dashboard, DAX measures, star schema |
| Modeling | Power BI semantic model | Relationships, calculated columns, time intelligence |

**Skills demonstrated:**

- Data cleaning and validation across 15+ check categories
- Grain-aware SQL (avoiding row multiplication across joins)
- Business rule validation and business-rule-aware date handling
- City/state normalization via alias mapping
- Analytical SQL — CTEs, window functions, conditional aggregation
- DAX — measures, time intelligence, filter context
- Star schema data modeling
- Root cause analysis and risk segmentation
- Executive communication and business recommendation writing

---

## Methods

### 1. Data Ingestion (Staging Layer)

All raw CSVs were loaded into MySQL staging tables with every column defined as `VARCHAR`. This deliberate design prevents type-conversion failures during load and keeps the raw data untouched until validation is complete.

### 2. Data Validation

Fifteen categories of checks were run against staging data:

- Row counts
- Empty string / NULL checks
- Format validation (regex for IDs, dates, numerics)
- Duplicate key detection
- Date format validation
- Chronological consistency (e.g., carrier date must not precede purchase date)
- Business rule validation (e.g., delivered orders must have delivery dates)
- Brazilian state code validation
- ZIP code format validation
- Geographic coordinate range validation
- Foreign-key / orphan checks
- Payment installment and value validation
- Review score range validation
- Product dimension validation
- Category translation completeness

Records identified as exceptions were **not deleted**. Each was handled during transformation according to its business meaning.

### 3. City and State Standardization

A `city_aliases` reference table was built to normalize city names across customers, sellers, and geolocation. It handled:

- Punctuation and whitespace variation
- Trailing state codes (e.g., "sao paulo sp")
- Accent removal (e.g., "São Paulo" → "sao paulo")
- Approximately 90 known variations of Brazilian city names
- Invalid values (numeric, email-like, empty) flagged as NULL

### 4. Transformation (Cleaned Layer)

Staging data was transformed into typed, keyed, normalized relational tables:

- Proper `PRIMARY KEY`, `FOREIGN KEY`, and `UNIQUE` constraints
- Business-rule-aware date handling:
  - `order_approved_at < order_purchase_timestamp` → NULL
  - `order_delivered_carrier_date < order_purchase_timestamp` → NULL
  - `order_delivered_customer_date < order_delivered_carrier_date` → NULL
  - Canceled / unavailable orders → delivery date NULL
- Invalid order statuses mapped to `'unknown'`
- Category translation backfilled for 2 missing categories
- Reviews use `UNIQUE(review_id, order_id)` because 547 orders have multiple reviews

### 5. Analytical Layer

Forty-plus SQL queries computed the metrics behind each finding. Four reusable views were created for Power BI consumption:

- `vw_order_analysis` — one row per order with delivery and value metrics
- `vw_seller_performance` — one row per seller with GMV, late rate, and review metrics
- `vw_category_performance` — one row per category with GMV, late rate, and review metrics
- `vw_monthly_sales` — one row per purchase-month with sales KPIs

### 6. Visualization

A 5-page Power BI dashboard presents the findings:

- Star schema with `dim_date` marked as the date table
- Eight Many-to-1 relationships
- Twenty-nine DAX measures (sales, delivery, reviews, retention, risk, time intelligence)
- Conditional formatting to signal risk
- Drill-through from the Priority Seller table to seller detail

---

## Key Insights

### 1. Retention is broad and marketplace-wide

Only **3.05%** of customers place a second order. The repeat rate varies by less than one percentage point across first-order value bands (from R$50 to R$500+), meaning the problem is **not segment-specific**. High-spending customers are, in fact, slightly *less* likely to return.

**Implication:** Growth is acquisition-dependent. The 2017 growth phase worked because new customers arrived at scale — not because customers returned.

### 2. Late delivery is the strongest driver of poor reviews

| Delay | Avg Review | Poor Review % |
|---|---|---|
| On time / early | **4.29** | 9.32% |
| 1–3 days late | 3.29 | 32.24% |
| 4–7 days late | **2.10** | 67.96% |
| 8–14 days late | 1.68 | 80.36% |
| 15+ days late | 1.72 | 78.88% |

Review scores collapse sharply once an order is **4 or more days late**. Past that point, approximately **76%** of reviews are poor (score ≤ 2), versus 9.32% for on-time orders.

**Implication:** The 4-day threshold is a specific, measurable operational target. Proactive customer notification around day 3 of lateness could preserve satisfaction.

### 3. Late delivery is geographically concentrated

| State | Late Rate | Orders |
|---|---|---|
| AL | 23.93% | 397 |
| MA | 19.67% | 717 |
| PI | 15.97% | 476 |
| CE | 15.32% | 1,279 |
| BA | 14.04% | 3,256 |
| **RJ** | **13.47%** | **12,350** |
| SP | 5.89% | 40,501 |

Rio de Janeiro stands out as the largest late-rate problem among high-volume states — 12,350 orders at a 13.47% late rate, which is **2.3× São Paulo's rate**.

**Implication:** RJ deserves a dedicated last-mile logistics investigation.

### 4. Fifteen sellers carry R$518,557 of GMV at risk

Sellers with delivered GMV ≥ R$20,000 and late rate ≥ 15% represent:

| Metric | Value |
|---|---|
| Priority sellers | 15 |
| Combined GMV at risk | R$518,557.64 |
| Total orders | 2,552 |
| Late orders | 499 |
| Average late rate | 22.65% |
| Average poor review rate | 29.03% |

**Implication:** This is a concrete, quantified intervention list — not a general concern.

### 5. Two distinct seller risk profiles exist

The seller analysis revealed two patterns that require different interventions:

- **Logistics failure:** High late rate (20%+), moderate review score. Products are acceptable; delivery is broken.
- **Quality failure:** Moderate late rate (10–15%), extreme poor review rate (30–50%). Delivery works; product or service quality fails.

**Example of quality failure:** A seller with R$237,562 GMV, a 13.37% late rate, and **29.35% poor reviews**. A late-rate-only filter would have missed this seller entirely.

**Implication:** Seller risk scoring must use both late rate AND poor review rate.

### 6. Freight correlates with lateness

Late delivery rates rise steadily with freight cost:

| Freight band | Late rate |
|---|---|
| ≤ R$10 | 6.22% |
| R$11–20 | 7.78% |
| R$21–30 | 9.07% |
| R$31–50 | 9.26% |
| R$51–100 | 9.64% |
| R$100+ | 11.13% |

**Implication:** Higher-freight customers are already paying more for shipping — and are also more likely to experience late delivery. This compounds the customer experience problem.

---

## Dashboard

The Power BI dashboard has five pages, each focused on a different layer of the business.

### Page 1 — Executive Overview

Six KPI cards (GMV, orders, AOV, average review, late rate, repeat rate), monthly GMV and orders trends, top categories, order status distribution, and a Key Insights panel. Answers: **how is the marketplace performing right now?**

### Page 2 — Sales & Growth

Category, state, and time breakdowns. AOV by category. 2017 vs 2018 monthly comparison. Answers: **where is revenue coming from, and how has it evolved?**

### Page 3 — Logistics

Late rate by state. Delay bucket distribution. Freight band vs late rate. Top 20 late-rate sellers. Answers: **where is late delivery concentrated and what drives it?**

### Page 4 — Customer Experience

Delay bucket vs average review score. Review score distribution. Poor review rate by state. Quality risk seller scatter. Answers: **what drives poor reviews, and which sellers have quality problems?**

### Page 5 — Seller Action Center

Priority seller table with drill-through. Two-dimensional risk matrix (GMV × poor review rate). GMV at risk by state. Answers: **which sellers should Olist intervene with, and how?**

---

## How to Run This Project

### Prerequisites

- MySQL 8.0 or higher
- Power BI Desktop (latest version)
- The Olist CSV files from Kaggle

### Steps

1. **Download the dataset** from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce).

2. **Run the SQL scripts in order:**

   ```
   sql/01_staging_schema.sql         — creates staging tables
   sql/02_staging_ingestion.sql      — loads raw CSVs
   sql/03_normalized_city_reference_table.sql — builds city_aliases
   sql/04_cleaned_schema_and_ingestion.sql    — creates cleaned tables
   sql/05_analytics_views.sql        — creates the analytical views

   ```

   Update the `LOAD DATA LOCAL INFILE` paths in `02_staging_ingestion.sql` to point to the CSV files on your machine.

3. **Open the Power BI file:**
   - `powerbi/Olist_Analytics_Final.pbix`
   - Update the MySQL connection to your local instance
   - Refresh the data

4. **Explore the dashboard** — 5 pages, with slicers and drill-through enabled.

---

## Result Conclusion

The analysis confirms that Olist's growth plateau in 2018 was not caused by a marketing failure or market saturation. It was caused by a **customer experience problem** that prevents repeat purchasing:

- 96.95% of customers buy once and never return
- Late delivery — which affects 8.11% of orders — is associated with a **2.19-point drop** in average review score
- The late-delivery problem is concentrated: 15 sellers, a handful of states, and high-freight orders
- The customers most affected are also the ones paying the most for shipping

The findings point to a clear conclusion: **improving delivery performance is the single highest-leverage operational improvement Olist can make.** Late delivery is not just an operational metric — it drives poor reviews, which drive non-return, which drives the retention problem that limits growth.

The recommendations are:

1. **Prioritize the 15 identified high-revenue sellers** for operational intervention
2. **Investigate Rio de Janeiro last-mile logistics** (13.47% late rate on 12,350 orders)
3. **Target a 4-day maximum delivery delay** — past that, satisfaction is unrecoverable
4. **Reframe retention as a delivery problem** — the 3.05% repeat rate is an experience issue, not a marketing issue

---

## Repository Structure

```
olist-ecommerce-analytics/
├── README.md
├── OLIST_ANALYTICS_INSIGHT.md
├── notebook/
│   ├── 03_data_validation_report.sql
│   └── 06_analytics_query_log.sql
├── sql/
│   ├── 01_staging_schema.sql
│   ├── 02_staging_ingestion.sql
│   ├── 03_data_validation_report.sql
│   ├── 04_normalized_city_reference_table.sql
│   ├── 05_cleaned_schema_and_ingestion.sql
│   ├── 06_analytics_query_log.sql
│   └── 07_analytics_views.sql
├── powerbi/
│   └── Olist_Analytics_Final.pbix
├── screenshots/
│   ├── page1-executive.png
│   ├── page2-sales.png
│   ├── page3-logistics.png
│   ├── page4-customer-experience.png
│   └── page5-seller-action.png
└── data/
    └── README.md
```

---

## Author

**[Vivek Singh]**
[LinkedIn](https://linkedin.com/in/--vivek-singh) · [Email](mailto:imvks15@gmail.com)
