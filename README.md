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

Categories of checks were run against staging data validating both data and business rules.
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
- Business-rule-aware date handling
- Category translation backfilled for 2 missing categories

### 5. Analytical Layer

Forty-plus SQL queries computed the metrics behind each finding. Four reusable views were created for Power BI consumption:

- `vw_order_analysis` — one row per order with delivery and value metrics
- `vw_seller_performance` — one row per seller with GMV, late rate, and review metrics
- `vw_category_performance` — one row per category with GMV, late rate, and review metrics
- `vw_monthly_sales` — one row per purchase-month with sales KPIs

### 6. Visualization

A 5-page Power BI dashboard presents the findings:

- Star schema with `dim_date` marked as the date table
- Many-to-1 relationships
- DAX measures (sales, delivery, reviews, retention, risk, time intelligence)
- Conditional formatting to signal risk
- Drill-through from the Priority Seller table to seller detail

---

## Key Insights

**1. Retention is marketplace-wide, not segment-specific**

**2. Late delivery is the strongest driver of poor reviews**

**3. Late delivery is geographically concentrated**

**4. 15 priority sellers represent R$518,557.64 GMV at risk**

**5.  Two distinct seller risk profiles exist (logistics failure and quality failure)**

**6. Freight cost correlates monotonically with late delivery rate (6.22% → 11.13%)**

---

## Dashboard

The Power BI dashboard has five pages, each focused on a different layer of the business.

### Page 1 — [Executive Overview](screenshots/page1-executive_overview.png)

Six KPI cards (GMV, orders, AOV, average review, late rate, repeat rate), monthly GMV and orders trends, top categories, order status distribution, and a Key Insights panel. Answers: **how is the marketplace performing right now?**

### Page 2 — [Sales & Growth](screenshots/page2-sales_&_growth.png)

Category, state, and time breakdowns. AOV by category. 2017 vs 2018 monthly comparison. Answers: **where is revenue coming from, and how has it evolved?**

### Page 3 — [Logistics](screenshots/page3-logistics_&_delivery_performance.png)

Late rate by state. Delay bucket distribution. Freight band vs late rate. Top 20 late-rate sellers. Answers: **where is late delivery concentrated and what drives it?**

### Page 4 — [Customer Experience](screenshots/page4-customer-experience.png)

Delay bucket vs average review score. Review score distribution. Poor review rate by state. Quality risk seller scatter. Answers: **what drives poor reviews, and which sellers have quality problems?**

### Page 5 — [Seller Action Center](screenshots/page5-seller_action_center.png)

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
   sql/01_staging_schema.sql                  — creates staging tables
   sql/02_staging_ingestion.sql               — loads raw CSVs
   sql/03_city_aliases.sql                    — builds city_aliases (optional for this project but needed for `04_cleaned_schema_and_ingestion` to run)
   sql/04_cleaned_schema_and_ingestion.sql    — creates cleaned tables
   sql/05_analytics_views.sql                 — creates the analytical views

   ```

   Update the `LOAD DATA LOCAL INFILE` paths in `02_staging_ingestion.sql` to point to the CSV files on your machine.

3. **Open the Power BI file:**
   - `powerbi/Olist_dashboard.pbix`
   - Update the MySQL connection to your local instance
   - Refresh the data

4. **Explore the dashboard** — 5 pages, with slicers and drill-through enabled.

---

## Repository Structure

```
olist-ecommerce-analytics/
├── README.md
├── analytics_insights.md
├── powerbi/
│   └── Olist_dashboard.pbix
├── analysis/
│   ├── 01_staging_data_&_business-rule__validation.sql
│   └── 02_analytics_query_log.sql
├── sql/
│   ├── 01_staging_schema.sql
│   ├── 02_staging_ingestion.sql
│   ├── 03_city_aliases.sql
│   ├── 04_cleaned_schema_and_ingestion.sql
│   └── 05_analytics_views.sql
├── screenshots/
│   ├── page1-executive_overview.png
│   ├── page2-sales_&_growth.png
│   ├── page3-logistics_&_delivery_performance.png
│   ├── page4-customer_experience.png
│   └── page5-seller_action_center.png
└── 
```
## Future Work
  - **Payment Behavior Analysis**
  - **Seller Lifecycle Analysis**
  - **Order Lifecycle Analysis**
  - **Geographic Drill-Down to City Level**
  - **Review Response Time affecting customer retention**
  - **Marketing funnel analysis**
---

## Author

**Vivek Singh**
[LinkedIn](https://linkedin.com/in/--vivek-singh) · [Email](mailto:imvks15@gmail.com)
