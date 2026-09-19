# Olist E-Commerce Analytics

**Stack:** MySQL (analysis) → Power BI (visualization)
**Dataset:** Brazilian E-Commerce Public Dataset by Olist (Sep 2016 – Oct 2018)

---

## Section 1 — Executive Summary

### Business Problem

Olist is a Brazilian e-commerce marketplace connecting small sellers to customers across the country. Management wants to understand:

> **How can Olist increase marketplace growth while improving customer experience and operational efficiency?**

This project analyzes 99,441 orders spanning September 2016 to October 2018 to answer three connected questions:

1. **Where is Olist's growth coming from, and is it sustainable?**
2. **What drives poor customer satisfaction?**
3. **Which specific operational factors — sellers, categories, geography — should Olist prioritize to improve?**

### Approach

The analysis follows a five-layer data pipeline:

```
Raw CSV → Staging (VARCHAR) → Validation → Transformed (typed, keyed) → Analytical Layer → Insights
```

- **MySQL** for data modeling, business rule validation, and analytical SQL
- **Power BI** for interactive visualization and executive reporting
- **DAX** for business metric definitions

---

## Section 2 — Dataset & Methodology

### Data Source

The Brazilian E-Commerce Public Dataset by Olist (Kaggle, 2018) contains 9 relational tables:

| Table | Grain | Rows |
|---|---|---|
| `olist_customers` | 1 row per customer_id | 99,441 |
| `olist_orders` | 1 row per order | 99,441 |
| `olist_order_items` | 1 row per item in an order | 112,650 |
| `olist_order_payments` | 1 row per payment sequence | 103,886 |
| `olist_order_reviews` | 1 row per review_id | 99,223 |
| `olist_products` | 1 row per product | 32,951 |
| `olist_sellers` | 1 row per seller | 3,095 |
| `olist_geolocation` | 1 row per coordinate | ~1M |
| `olist_product_category_name_translation` | 1 row per category | 71 |

### Critical Grain Rules

The single most important modeling decision was respecting grain boundaries:

- **`olist_orders`** — 1 row per **order**
- **`olist_order_items`** — 1 row per **item**, not per order
- **`olist_order_payments`** — 1 row per **payment sequence**, not per order
- **`olist_order_reviews`** — 1 row per **review**, with 547 orders having multiple reviews

**Every revenue and metric calculation respects these grain boundaries.** AOV is calculated at order grain; GMV at item grain; reviews deduplicated at order grain before joining.

### Data Cleaning Approach

1. **Staging layer** — raw CSVs ingested as `VARCHAR` for inspection
2. **Validation** — duplicates, NULLs, orphan records, date ranges, business-rule violations
3. **Transformed layer** — typed columns, primary keys, foreign keys, category translation joined, state names normalized, city standardization applied
4. **Post-transformation audit** — row-count reconciliation, PK uniqueness, FK integrity

### Key Definitions

| Metric | Definition |
|---|---|
| Delivered order | `order_status = 'delivered'` |
| Delivered order (in-scope) | Delivered AND both delivery + estimated timestamps present |
| GMV | `SUM(price + freight_value)` at item grain |
| AOV | GMV ÷ distinct orders (at order grain) |
| Late order | `order_delivered_customer_date > order_estimated_delivery_date` |
| Poor review | `review_score <= 2` |
| Repeat customer | Customer with ≥ 2 distinct orders (using `customer_unique_id`) |

---

## Section 3 — Sales Performance Analysis

### 3.1 Business Question

> *How is Olist's marketplace performing in terms of revenue, orders, and customer acquisition over time?*

### 3.2 SQL Query — Sales baseline

```sql
SELECT
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT oi.order_id) AS orders_with_items,
    COUNT(DISTINCT CASE WHEN o.order_status = 'delivered' THEN o.order_id END) AS delivered_orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    ROUND(SUM(CASE WHEN o.order_status = 'delivered' THEN oi.price + oi.freight_value END), 2) AS delivered_gmv,
    ROUND(
        SUM(CASE WHEN o.order_status = 'delivered' THEN oi.price + oi.freight_value END)
        / NULLIF(COUNT(DISTINCT CASE WHEN o.order_status = 'delivered' THEN o.order_id END), 0),
        2
    ) AS delivered_aov
FROM olist_orders o
JOIN olist_order_items oi ON o.order_id = oi.order_id
JOIN olist_customers c ON o.customer_id = c.customer_id;
```

### 3.3 SQL Query — Monthly sales trend

```sql
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(DISTINCT o.order_id) AS orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS order_value
FROM olist_orders o
JOIN olist_order_items oi ON o.order_id = oi.order_id
JOIN olist_customers c ON o.customer_id = c.customer_id
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;
```

### 3.4 Findings

**Marketplace baseline (Query 3.2):**

| Metric | Value |
|---|---|
| Total orders | 99,441 |
| Orders with items | 98,666 |
| Delivered orders | 96,478 |
| Unique customers | 95,420 |
| Delivered GMV | R$15,419,773.75 |
| Delivered AOV | R$159.83 |

**Monthly trend (Query 3.3):**

- Sep 2016 – Jan 2017: Ramp-up (3 → 789 orders/month)
- Feb 2017 – Oct 2017: Steady growth (1,733 → 4,568 orders/month)
- **Nov 2017: Sharp spike (7,451 orders)**
- Dec 2017 – Aug 2018: Plateau at 6,100–7,200 orders/month
- Sep 2018: Dataset trail-off (1 order)

### 3.5 Business Insight

> Olist reached a **stable plateau of ~6,500 orders/month** by mid-2018 after a growth phase through 2017.
>
> The plateau suggests **the marketplace has saturated its initial growth curve** and future growth must come from either (a) new customer acquisition (already at 95,420 unique customers) or (b) increased customer lifetime value. Given the retention findings (Section 5), path (b) is severely underdeveloped.

---

## Section 4 — Growth Driver Analysis (November 2017 Spike)

### 4.1 Business Question

> *What caused the dramatic order value increase in November 2017 (+53.27% MoM)?*

### 4.2 SQL Query — Oct vs Nov order-level metrics

```sql
WITH order_level AS (
    SELECT
        o.order_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        c.customer_unique_id,
        SUM(oi.price + oi.freight_value) AS order_value,
        COUNT(*) AS item_count
    FROM olist_orders o
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    JOIN olist_customers c ON o.customer_id = c.customer_id
    WHERE o.order_purchase_timestamp >= '2017-10-01'
      AND o.order_purchase_timestamp < '2017-12-01'
    GROUP BY o.order_id, DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m'), c.customer_unique_id
),
monthly AS (
    SELECT
        order_month,
        COUNT(*) AS orders,
        COUNT(DISTINCT customer_unique_id) AS customers,
        ROUND(SUM(order_value), 2) AS order_value,
        ROUND(AVG(order_value), 2) AS aov,
        ROUND(AVG(item_count), 2) AS avg_items_per_order
    FROM order_level
    GROUP BY order_month
)
SELECT
    order_month,
    orders,
    customers,
    order_value,
    aov,
    avg_items_per_order,
    LAG(orders) OVER (ORDER BY order_month) AS prev_orders,
    ROUND(100.0 * (orders - LAG(orders) OVER (ORDER BY order_month))
        / NULLIF(LAG(orders) OVER (ORDER BY order_month), 0), 2) AS pct_change_orders,
    ROUND(100.0 * (order_value - LAG(order_value) OVER (ORDER BY order_month))
        / NULLIF(LAG(order_value) OVER (ORDER BY order_month), 0), 2) AS pct_change_value,
    ROUND(100.0 * (aov - LAG(aov) OVER (ORDER BY order_month))
        / NULLIF(LAG(aov) OVER (ORDER BY order_month), 0), 2) AS pct_change_aov
FROM monthly
ORDER BY order_month;
```

### 4.3 SQL Query — New vs existing customers

```sql
WITH first_purchase AS (
    SELECT
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_order_date
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
),
november_orders AS (
    SELECT
        o.order_id,
        c.customer_unique_id,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp >= '2017-11-01'
      AND o.order_purchase_timestamp < '2017-12-01'
    GROUP BY o.order_id, c.customer_unique_id
),
grouped AS (
    SELECT
        CASE
            WHEN fp.first_order_date >= '2017-11-01'
             AND fp.first_order_date < '2017-12-01'
            THEN 'New Customer'
            ELSE 'Existing Customer'
        END AS customer_type,
        COUNT(DISTINCT no.customer_unique_id) AS customers,
        COUNT(DISTINCT no.order_id) AS orders,
        ROUND(SUM(no.order_value), 2) AS order_value,
        ROUND(SUM(no.order_value) / COUNT(DISTINCT no.order_id), 2) AS aov
    FROM november_orders no
    JOIN first_purchase fp ON no.customer_unique_id = fp.customer_unique_id
    GROUP BY customer_type
)
SELECT
    customer_type,
    customers,
    orders,
    order_value,
    aov,
    ROUND(100.0 * customers / SUM(customers) OVER (), 2) AS customer_share_pct
FROM grouped
ORDER BY customers DESC;
```

### 4.4 Findings

**Oct vs Nov (Query 4.2):**

| Metric | Oct 2017 | Nov 2017 | Change |
|---|---|---|---|
| Orders | 4,568 | 7,451 | +63.11% |
| Customers | 4,501 | 7,342 | +63.12% |
| Order value | R$769,312 | R$1,179,144 | +53.27% |
| AOV | R$168.41 | R$158.25 | −6.03% |
| Items/order | 1.17 | 1.16 | −0.85% |

**New vs Existing (Query 4.3):**

| Customer Type | Customers | Share | Orders | Order Value | AOV |
|---|---|---|---|---|---|
| New | 7,216 | 98.3% | 7,319 | R$1,161,028.82 | R$158.63 |
| Existing | 126 | 1.7% | 132 | R$18,114.95 | R$137.23 |

### 4.5 Business Insight

> **November's growth was entirely volume-driven, not value-driven.** Order volume rose 63.11% while AOV *declined* 6.03% — meaning new customers bought smaller baskets, but there were far more of them.
>
> **98.3% of November customers were first-time buyers.** This is characteristic of a marketing campaign or promotional event (e.g., Black Friday), but the Olist dataset does not contain campaign data, so causality cannot be confirmed.
>
> **The critical takeaway:** If the business's growth depends on spikes of new customers who never return, then the retention problem (Section 5) is not a background concern — it's the central structural issue.

---

## Section 5 — Customer Retention Analysis

### 5.1 Business Question

> *How many customers make repeat purchases, and does retention differ by customer value?*

### 5.2 SQL Query — Repeat rate

```sql
WITH customer_orders AS (
    SELECT DISTINCT
        c.customer_unique_id,
        o.order_id
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON o.order_id = oi.order_id
),
customer_order_counts AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS order_count
    FROM customer_orders
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN order_count = 1 THEN 1 ELSE 0 END) AS one_time_customers,
    SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN order_count = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS one_time_rate_pct,
    ROUND(100.0 * SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM customer_order_counts;
```

### 5.3 SQL Query — Return timing distribution and true repeat rate

```sql
-- Part A: Return bucket distribution
WITH customer_orders AS (
    SELECT DISTINCT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON o.order_id = oi.order_id
),
ranked AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp, order_id
        ) AS order_number
    FROM customer_orders
),
first_second AS (
    SELECT
        customer_unique_id,
        MAX(CASE WHEN order_number = 1 THEN order_purchase_timestamp END) AS first_order_date,
        MAX(CASE WHEN order_number = 2 THEN order_purchase_timestamp END) AS second_order_date
    FROM ranked
    WHERE order_number <= 2
    GROUP BY customer_unique_id
),
return_days AS (
    SELECT
        customer_unique_id,
        DATEDIFF(second_order_date, first_order_date) AS days_to_second_order
    FROM first_second
    WHERE second_order_date IS NOT NULL
),
total AS (
    SELECT COUNT(DISTINCT customer_unique_id) AS total_customers
    FROM customer_orders
)
SELECT
    CASE
        WHEN days_to_second_order = 0 THEN '0 days (same day)'
        WHEN days_to_second_order <= 30 THEN '1-30 days'
        WHEN days_to_second_order <= 60 THEN '31-60 days'
        WHEN days_to_second_order <= 90 THEN '61-90 days'
        WHEN days_to_second_order <= 180 THEN '91-180 days'
        WHEN days_to_second_order <= 365 THEN '181-365 days'
        ELSE '365+ days'
    END AS return_bucket,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_of_repeat_pct,
    ROUND(
        100.0 * COUNT(*) / (SELECT total_customers FROM total),
        2
    ) AS share_of_all_customers_pct
FROM return_days
GROUP BY return_bucket
ORDER BY MIN(days_to_second_order);

-- Part B: True repeat rate (excluding same-day order-splitting)
WITH customer_orders AS (
    SELECT DISTINCT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON o.order_id = oi.order_id
),
ranked AS (
    SELECT
        customer_unique_id,
        order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY order_purchase_timestamp, order_id
        ) AS order_number
    FROM customer_orders
),
first_second AS (
    SELECT
        customer_unique_id,
        MAX(CASE WHEN order_number = 1 THEN order_purchase_timestamp END) AS first_order_date,
        MAX(CASE WHEN order_number = 2 THEN order_purchase_timestamp END) AS second_order_date
    FROM ranked
    WHERE order_number <= 2
    GROUP BY customer_unique_id
)
SELECT
    (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_orders) AS total_customers,
    SUM(CASE WHEN DATEDIFF(second_order_date, first_order_date) = 0 THEN 1 ELSE 0 END) AS same_day_repeats,
    SUM(CASE WHEN DATEDIFF(second_order_date, first_order_date) > 0 THEN 1 ELSE 0 END) AS true_repeats,
    ROUND(
        100.0 * SUM(CASE WHEN DATEDIFF(second_order_date, first_order_date) > 0 THEN 1 ELSE 0 END)
        / (SELECT COUNT(DISTINCT customer_unique_id) FROM customer_orders),
        2
    ) AS true_repeat_rate_pct
FROM first_second
WHERE second_order_date IS NOT NULL;
```

### 5.4 SQL Query — Retention by first-order value

```sql
WITH first_order AS (
    SELECT
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_order_date
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
),
first_order_value AS (
    SELECT
        fo.customer_unique_id,
        SUM(oi.price + oi.freight_value) AS first_order_value
    FROM first_order fo
    JOIN olist_orders o ON o.order_purchase_timestamp = fo.first_order_date
    JOIN olist_customers c ON o.customer_id = c.customer_id
        AND c.customer_unique_id = fo.customer_unique_id
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    GROUP BY fo.customer_unique_id
),
customer_counts AS (
    SELECT DISTINCT c.customer_unique_id, o.order_id
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON o.order_id = oi.order_id
),
customer_orders AS (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS order_count
    FROM customer_counts GROUP BY customer_unique_id
)
SELECT
    CASE
        WHEN fov.first_order_value <= 50 THEN '1. ≤ R$50'
        WHEN fov.first_order_value <= 100 THEN '2. R$51-100'
        WHEN fov.first_order_value <= 200 THEN '3. R$101-200'
        WHEN fov.first_order_value <= 500 THEN '4. R$201-500'
        ELSE '5. R$500+'
    END AS first_order_value_band,
    COUNT(*) AS customers,
    SUM(CASE WHEN co.order_count >= 2 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN co.order_count >= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM first_order_value fov
JOIN customer_orders co ON fov.customer_unique_id = co.customer_unique_id
GROUP BY first_order_value_band
ORDER BY first_order_value_band;
```

### 5.5 SQL Query — One-time vs repeat customer value

```sql
WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
),
customer_value AS (
    SELECT
        c.customer_unique_id,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
),
grouped AS (
    SELECT
        CASE
            WHEN coc.order_count = 1 THEN 'One-time Customer'
            ELSE 'Repeat Customer'
        END AS customer_type,
        COUNT(*) AS customers,
        ROUND(SUM(cv.order_value), 2) AS total_order_value,
        ROUND(AVG(cv.order_value), 2) AS avg_customer_value
    FROM customer_order_counts coc
    JOIN customer_value cv ON coc.customer_unique_id = cv.customer_unique_id
    GROUP BY customer_type
)
SELECT
    customer_type,
    customers,
    total_order_value,
    avg_customer_value,
    ROUND(
        MAX(avg_customer_value) OVER () / MIN(avg_customer_value) OVER (),
        2
    ) AS value_ratio
FROM grouped
ORDER BY avg_customer_value DESC;
```

### 5.6 Findings

**Repeat rate (Query 5.2):**

| Segment | Customers | Share |
|---|---|---|
| One-time | 92,507 | 96.95% |
| Repeat | 2,913 | 3.05% |

**Return timing (Query 5.3, Part A):**

| Bucket | Customers | Share of repeats | Share of all customers |
|---|---|---|---|
| 0 days (same day) | 875 | 30.04% | 0.92% |
| 1–30 days | 603 | 20.70% | 0.63% |
| 31–60 days | 313 | 10.74% | 0.33% |
| 61–90 days | 201 | 6.90% | 0.21% |
| 91–180 days | 424 | 14.56% | 0.44% |
| 181–365 days | 411 | 14.11% | 0.43% |
| 365+ days | 86 | 2.95% | 0.09% |

**True repeat rate (Query 5.3, Part B):**

| Metric | Value |
|---|---|
| Total customers | 95,420 |
| Same-day repeats | 875 |
| True repeats | 2,038 |
| **True repeat rate** | **2.14%** |

**Retention by first-order value (Query 5.4):**

| First-order band | Customers | Repeat rate |
|---|---|---|
| ≤ R$50 | 16,239 | 3.05% |
| R$51–100 | 28,936 | 2.89% |
| R$101–200 | 30,707 | 3.03% |
| R$201–500 | 15,390 | 3.53% |
| R$500+ | 4,148 | 2.56% |

**Customer value (Query 5.5):**

| Customer type | Customers | Total value | Avg value | Ratio |
|---|---|---|---|---|
| One-time | 92,507 | R$14,939,106.99 | R$161.49 | 1.00 |
| Repeat | 2,913 | R$904,446.25 | R$310.49 | 1.92 |

### 5.7 Business Insight

> **Three critical findings:**
>
> **1. Olist has a marketplace-wide retention problem.** Only 3.05% of customers place a second order (2.14% excluding same-day order-splitting). Of those, 30.04% place their second order on the same calendar day as their first — which is likely order-splitting rather than genuine repurchase.
>
> **2. Retention is not segment-specific.** Repeat rates are essentially flat across first-order value bands (2.56%–3.53%). High-spending customers (R$500+) are actually the **least likely** to return. This rules out the "target the best customers" strategy — the problem is broad.
>
> **3. Returning customers exhibit bimodal behavior.** Of the 2,913 who return, 30.04% come back same-day and 20.70% within 30 days (fast returners), while 41% take 3–12 months (slow returners). This suggests two distinct customer types and two different reactivation strategies.
>
> **Implication:** Because 96.95% of customers buy once and never return, Olist's growth model is acquisition-dependent. Combined with the finding that November 2017 growth was 98.3% new-customer-driven, this means **the business is on a treadmill — it must acquire more customers each period just to sustain revenue.**

---

## Section 6 — Delivery Performance Analysis

### 6.1 Business Question

> *How well is Olist meeting its promised delivery dates, and what is the impact of late delivery on customer satisfaction?*

### 6.2 SQL Query — Delivery baseline

```sql
SELECT
    COUNT(*) AS delivered_orders,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(AVG(DATEDIFF(order_estimated_delivery_date, order_purchase_timestamp)), 1) AS avg_estimated_days,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date)), 1) AS avg_delay_days,
    SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    ROUND(
        100.0 * SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS late_rate_pct
FROM olist_orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;
```

### 6.3 SQL Query — Delay bucket vs review score

```sql
-- Part A: Per-bucket breakdown
SELECT
    CASE
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) <= 0 THEN '1. On Time / Early'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 1 AND 3 THEN '2. 1-3 days late'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 4 AND 7 THEN '3. 4-7 days late'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 8 AND 14 THEN '4. 8-14 days late'
        ELSE '5. 15+ days late'
    END AS delay_bucket,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) AS poor_reviews,
    ROUND(
        100.0 * SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
        / COUNT(DISTINCT o.order_id),
        2
    ) AS poor_review_rate_pct
FROM olist_orders o
JOIN olist_order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY delay_bucket
ORDER BY delay_bucket;

-- Part B: Combined 4+ days late vs on-time/minor delay
WITH delay_level AS (
    SELECT
        o.order_id,
        CASE
            WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) <= 3
            THEN 'On time / minor delay'
            ELSE '4+ days late'
        END AS delay_category,
        r.review_score
    FROM olist_orders o
    JOIN olist_order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    delay_category,
    COUNT(DISTINCT order_id) AS orders,
    ROUND(AVG(review_score), 2) AS avg_review_score,
    SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS poor_reviews,
    ROUND(
        100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(DISTINCT order_id),
        2
    ) AS poor_review_rate_pct
FROM delay_level
GROUP BY delay_category
ORDER BY delay_category;
```

### 6.4 SQL Query — Late rate by state

```sql
SELECT
    c.customer_state,
    COUNT(*) AS delivered_orders,
    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    ROUND(
        100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END)
        / COUNT(*),
        2
    ) AS late_rate_pct
FROM olist_orders o
JOIN olist_customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(*) >= 100
ORDER BY late_rate_pct DESC;

-- RJ vs SP ratio
SELECT
    rj.delivered_orders AS rj_orders,
    rj.late_rate_pct AS rj_late_rate,
    sp.delivered_orders AS sp_orders,
    sp.late_rate_pct AS sp_late_rate,
    ROUND(rj.late_rate_pct / NULLIF(sp.late_rate_pct, 0), 2) AS rj_vs_sp_ratio
FROM
    (SELECT COUNT(*) AS delivered_orders,
            ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_rate_pct
     FROM olist_orders o
     JOIN olist_customers c ON o.customer_id = c.customer_id
     WHERE o.order_status = 'delivered'
       AND o.order_delivered_customer_date IS NOT NULL
       AND o.order_estimated_delivery_date IS NOT NULL
       AND c.customer_state = 'RJ') rj,
    (SELECT COUNT(*) AS delivered_orders,
            ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_rate_pct
     FROM olist_orders o
     JOIN olist_customers c ON o.customer_id = c.customer_id
     WHERE o.order_status = 'delivered'
       AND o.order_delivered_customer_date IS NOT NULL
       AND o.order_estimated_delivery_date IS NOT NULL
       AND c.customer_state = 'SP') sp;
```

### 6.5 SQL Query — Freight band vs lateness

```sql
WITH order_level AS (
    SELECT
        o.order_id,
        SUM(oi.freight_value) AS freight_value,
        CASE
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
            ELSE 0
        END AS is_late
    FROM olist_orders o
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY o.order_id, o.order_delivered_customer_date, o.order_estimated_delivery_date
)
SELECT
    CASE
        WHEN freight_value <= 10 THEN '1. ≤ R$10'
        WHEN freight_value <= 20 THEN '2. R$11-20'
        WHEN freight_value <= 30 THEN '3. R$21-30'
        WHEN freight_value <= 50 THEN '4. R$31-50'
        WHEN freight_value <= 100 THEN '5. R$51-100'
        ELSE '6. R$100+'
    END AS freight_band,
    COUNT(*) AS orders,
    ROUND(AVG(is_late) * 100, 2) AS late_rate_pct
FROM order_level
GROUP BY freight_band
ORDER BY freight_band;
```

### 6.6 Findings

**Delivery baseline (Query 6.2):**

| Metric | Value |
|---|---|
| Delivered orders | 96,447 |
| Avg actual delivery | 12.5 days |
| Avg estimated delivery | 24.4 days |
| Avg delay | −11.9 days |
| Late orders | 7,826 |
| **Late rate** | **8.11%** |

**Delay vs review — per bucket (Query 6.3, Part A):**

| Delay bucket | Orders | Avg review | Poor review % |
|---|---|---|---|
| On Time / Early | 89,419 | 4.29 | 9.32% |
| 1–3 days late | 1,852 | 3.29 | 32.24% |
| 4–7 days late | 1,748 | 2.10 | 67.96% |
| 8–14 days late | 1,446 | 1.68 | 80.36% |
| 15+ days late | 1,335 | 1.72 | 78.88% |

**Delay vs review — combined bucket (Query 6.3, Part B):**

| Delay category | Orders | Avg review | Poor review % |
|---|---|---|---|
| On time / minor delay | 91,271 | 4.27 | 9.79% |
| 4+ days late | 4,529 | 1.82 | 75.58% |

**Late rate by state (Query 6.4):**

| State | Late rate | Orders | Late orders |
|---|---|---|---|
| AL | 23.93% | 397 | 95 |
| MA | 19.67% | 717 | 141 |
| PI | 15.97% | 476 | 76 |
| CE | 15.32% | 1,279 | 196 |
| BA | 14.04% | 3,256 | 457 |
| **RJ** | **13.47%** | **12,350** | **1,664** |
| SP | 5.89% | 40,501 | 2,387 |
| PR | 5.00% | 4,923 | 246 |

**RJ vs SP ratio (Query 6.4):**

| rj_orders | rj_late_rate | sp_orders | sp_late_rate | rj_vs_sp_ratio |
|---|---|---|---|---|
| 12,350 | 13.47% | 40,501 | 5.89% | **2.29** |

**Freight band vs lateness (Query 6.5):**

| Freight band | Orders | Late rate |
|---|---|---|
| ≤ R$10 | 11,073 | 6.22% |
| R$11–20 | 52,387 | 7.78% |
| R$21–30 | 16,303 | 9.07% |
| R$31–50 | 10,616 | 9.26% |
| R$51–100 | 5,008 | 9.64% |
| R$100+ | 1,060 | 11.13% |

### 6.7 Business Insight

> **Finding 1 — Olist deliberately over-promises.** Average actual delivery (12.5 days) is half of the estimate (24.4 days).
>
> **Finding 2 — Late delivery is the strongest driver of poor reviews we found in the entire dataset.** On-time orders average **4.29** stars; orders 4–7 days late average **2.10** stars. Once an order is 4+ days late, **75.58% of reviews are poor (score ≤ 2)** vs 9.79% for on-time/minor-delay orders.
>
> **Finding 3 — The problem is geographic.** Rio de Janeiro (RJ) has a 13.47% late rate on 12,350 orders with **1,664 late orders** — 2.29× São Paulo's rate (5.89%). Northern states (AL, MA, PI, CE) have 15–24% late rates but much smaller volumes.
>
> **Finding 4 — The inflection point is 4 days.** 1–3 days late is annoying but forgivable (rating 3.29). Once past 4 days, satisfaction collapses. This suggests a **specific operational target: keep lateness under 4 days.**
>
> **Finding 5 — Freight correlates with lateness.** Late rates rise monotonically across freight bands: 6.22% (≤R$10) → 11.13% (R$100+).

---

## Section 7 — Seller Risk Segmentation

### 7.1 Business Question

> *Which sellers present the greatest business risk, and what type of intervention do they require?*

### 7.2 SQL Query — Marketplace baseline

```sql
SELECT
    COUNT(*) AS total_reviews,
    ROUND(AVG(review_score), 2) AS avg_review_score,
    SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS poor_reviews,
    ROUND(
        100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS poor_review_rate_pct
FROM olist_order_reviews;
```

### 7.3 SQL Query — Seller risk scorecard (per seller)

```sql
WITH seller_delivery AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS seller_gmv,
        SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
        ROUND(
            100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END)
            / COUNT(DISTINCT o.order_id),
            2
        ) AS late_rate_pct
    FROM olist_order_items oi
    JOIN olist_orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY oi.seller_id
),
seller_reviews AS (
    SELECT
        oi.seller_id,
        ROUND(AVG(r.review_score), 2) AS avg_review_score,
        ROUND(
            100.0 * SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
            / COUNT(DISTINCT o.order_id),
            2
        ) AS poor_review_rate_pct
    FROM olist_order_items oi
    JOIN olist_orders o ON oi.order_id = o.order_id
    JOIN olist_order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
)
SELECT
    d.seller_id,
    s.seller_state,
    d.delivered_orders,
    d.seller_gmv,
    d.late_orders,
    d.late_rate_pct,
    r.avg_review_score,
    r.poor_review_rate_pct,
    CASE
        WHEN d.seller_gmv >= 20000 AND d.late_rate_pct >= 15 THEN 'Priority Intervention'
        WHEN d.seller_gmv >= 20000 AND d.late_rate_pct >= 10 THEN 'Monitor'
        WHEN d.seller_gmv < 20000 AND d.late_rate_pct >= 20 THEN 'Investigate'
        ELSE 'Healthy'
    END AS risk_segment
FROM seller_delivery d
LEFT JOIN seller_reviews r ON d.seller_id = r.seller_id
LEFT JOIN olist_sellers s ON d.seller_id = s.seller_id
WHERE d.delivered_orders >= 30
ORDER BY
    CASE
        WHEN d.seller_gmv >= 20000 AND d.late_rate_pct >= 15 THEN 1
        WHEN d.seller_gmv >= 20000 AND d.late_rate_pct >= 10 THEN 2
        WHEN d.seller_gmv < 20000 AND d.late_rate_pct >= 20 THEN 3
        ELSE 4
    END,
    d.seller_gmv DESC;
```

### 7.4 SQL Query — Priority seller aggregates with marketplace comparison

```sql
WITH seller_delivery AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS seller_gmv,
        SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
        ROUND(
            100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END)
            / COUNT(DISTINCT o.order_id),
            2
        ) AS late_rate_pct
    FROM olist_order_items oi
    JOIN olist_orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY oi.seller_id
),
seller_reviews AS (
    SELECT
        oi.seller_id,
        ROUND(AVG(r.review_score), 2) AS avg_review_score,
        ROUND(
            100.0 * SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
            / COUNT(DISTINCT o.order_id),
            2
        ) AS poor_review_rate_pct
    FROM olist_order_items oi
    JOIN olist_orders o ON oi.order_id = o.order_id
    JOIN olist_order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
),
priority AS (
    SELECT
        COUNT(*) AS priority_sellers,
        ROUND(SUM(d.seller_gmv), 2) AS total_gmv_at_risk,
        SUM(d.delivered_orders) AS total_orders,
        SUM(d.late_orders) AS total_late_orders,
        ROUND(AVG(d.late_rate_pct), 2) AS avg_late_rate,
        ROUND(AVG(r.avg_review_score), 2) AS avg_review_score,
        ROUND(AVG(r.poor_review_rate_pct), 2) AS avg_poor_review_rate
    FROM seller_delivery d
    LEFT JOIN seller_reviews r ON d.seller_id = r.seller_id
    WHERE d.delivered_orders >= 30
      AND d.seller_gmv >= 20000
      AND d.late_rate_pct >= 15
),
marketplace AS (
    SELECT
        ROUND(
            100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END)
            / COUNT(*),
            2
        ) AS marketplace_late_rate,
        (SELECT ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 2)
         FROM olist_order_reviews) AS marketplace_poor_review_rate
    FROM olist_orders o
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
)
SELECT
    p.priority_sellers,
    p.total_gmv_at_risk,
    p.total_orders,
    p.total_late_orders,
    p.avg_late_rate,
    p.avg_review_score,
    p.avg_poor_review_rate,
    m.marketplace_late_rate,
    m.marketplace_poor_review_rate,
    ROUND(p.avg_late_rate / NULLIF(m.marketplace_late_rate, 0), 2) AS late_rate_ratio,
    ROUND(p.avg_poor_review_rate / NULLIF(m.marketplace_poor_review_rate, 0), 2) AS poor_review_ratio
FROM priority p
CROSS JOIN marketplace m;
```

### 7.5 SQL Query — Risk profile classification

```sql
WITH seller_metrics AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS seller_gmv,
        ROUND(
            100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END)
            / COUNT(DISTINCT o.order_id),
            2
        ) AS late_rate_pct
    FROM olist_order_items oi
    JOIN olist_orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY oi.seller_id
),
seller_review_metrics AS (
    SELECT
        oi.seller_id,
        ROUND(
            100.0 * SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END)
            / COUNT(DISTINCT o.order_id),
            2
        ) AS poor_review_rate_pct
    FROM olist_order_items oi
    JOIN olist_orders o ON oi.order_id = o.order_id
    JOIN olist_order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
)
SELECT
    CASE
        WHEN sm.late_rate_pct >= 15 AND COALESCE(srm.poor_review_rate_pct, 0) < 30 THEN 'Logistics Failure'
        WHEN sm.late_rate_pct < 15 AND COALESCE(srm.poor_review_rate_pct, 0) >= 30 THEN 'Quality Failure'
        WHEN sm.late_rate_pct >= 15 AND COALESCE(srm.poor_review_rate_pct, 0) >= 30 THEN 'Critical (Both)'
        ELSE 'Healthy'
    END AS risk_profile,
    COUNT(*) AS seller_count,
    ROUND(SUM(sm.seller_gmv), 2) AS combined_gmv,
    ROUND(AVG(sm.late_rate_pct), 2) AS avg_late_rate,
    ROUND(AVG(srm.poor_review_rate_pct), 2) AS avg_poor_review_rate
FROM seller_metrics sm
LEFT JOIN seller_review_metrics srm ON sm.seller_id = srm.seller_id
WHERE sm.delivered_orders >= 30
  AND sm.seller_gmv >= 20000
GROUP BY risk_profile
ORDER BY combined_gmv DESC;
```

### 7.6 Findings

**Marketplace baseline (Query 7.2):**

| Metric | Value |
|---|---|
| Avg review score (all) | 4.09 |
| Poor review rate (all) | 14.69% |

**Priority Intervention segment (Query 7.4):**

| Metric | Value |
|---|---|
| Number of priority sellers | **15** |
| Combined GMV at risk | **R$518,557.64** |
| Total orders | 2,552 |
| Late orders | 499 |
| Avg late rate | **22.65%** |
| Avg review score | **3.56** |
| Avg poor review rate | **29.03%** |
| Marketplace late rate | 8.11% |
| Marketplace poor review rate | 14.69% |
| Late rate ratio (priority vs marketplace) | **2.79** |
| Poor review ratio (priority vs marketplace) | **1.98** |

**Notable individual sellers (Query 7.3):**

| Seller ID (truncated) | State | GMV | Late % | Review | Poor review % |
|---|---|---|---|---|---|
| `81602554…` | SP | R$54,096 | 20.00% | 3.86 | 22.07% |
| `06a2c3af…` | MA | R$48,170 | 24.42% | 4.03 | 16.10% |
| `712e6ed8…` | SC | R$46,150 | 23.38% | 3.47 | 38.16% |
| `88460e8e…` | PR | R$36,259 | 23.98% | 3.37 | 40.00% |
| `897060da…` | SP | R$28,258 | 16.45% | 3.47 | 40.20% |
| `7c67e144…` | SP | R$237,562 | 13.37% | 3.35 | 29.35% |

**Risk profile classification (Query 7.5):**

Confirms two distinct seller failure patterns exist:
- **Logistics Failure:** high late rate (≥ 15%), moderate poor review rate (< 30%)
- **Quality Failure:** moderate late rate (< 15%), high poor review rate (≥ 30%)

### 7.7 Business Insight

> **Two distinct seller risk profiles emerged:**
>
> **Profile A — Logistics failure.** High late rate (20%+), moderate review score. These sellers move products but have carrier/warehouse issues. Example: `06a2c3af…` (MA) with 24.42% late rate on 389 orders.
>
> **Profile B — Product/service quality failure.** Moderate late rate (10–15%) but extreme poor review rate (30–50%). These sellers ship on time but the products or service are failing. Example: `7c67e144…` has R$237K GMV, 13.37% late rate, but a **29.35% poor review rate and 3.35 average rating** — the second-highest GMV seller in the entire marketplace.
>
> **The Profile B case is analytically critical:** A naive late-rate filter would have missed `7c67e144…` (it falls in "Monitor" not "Priority"). But its combination of scale (R$237K GMV) and quality failure (29.35% poor reviews) makes it arguably the highest-priority intervention in the entire marketplace.
>
> **This finding validates the need for two-dimensional risk scoring** — GMV × poor review rate — rather than relying on a single operational metric.

---

## Section 8 — Key Findings & Business Recommendations

### 8.1 Consolidated Findings

| # | Finding | Query | Impact |
|---|---|---|---|
| 1 | Retention is marketplace-wide, not segment-specific | Q5.2, Q5.3, Q5.4 | Growth depends entirely on new customer acquisition |
| 2 | Late delivery drives poor reviews | Q6.3 | Highest-leverage CX lever |
| 3 | The 4-day threshold is critical | Q6.3 | Specific operational target |
| 4 | Late delivery is geographically concentrated | Q6.4 | RJ: 13.47% on 12,350 orders, 2.29× SP |
| 5 | 15 sellers = R$518K GMV at risk | Q7.4 | Concrete intervention list |
| 6 | Two distinct seller risk profiles exist | Q7.5 | Different interventions needed |
| 7 | Freight correlates monotonically with lateness | Q6.5 | 6.22% → 11.13% across freight bands |

### 8.2 Business Recommendations

**Recommendation 1 — Prioritize the 15 Priority Intervention sellers**

*Evidence:* Query 7.4 — 15 sellers with combined GMV of R$518,557.64 and average late rate of 22.65% (2.79× the marketplace average of 8.11%).

*Action:* Operational outreach to each seller. Review carrier contracts, warehouse capacity, packaging processes. For sellers with high poor-review rates that aren't explained by lateness (Profile B), investigate product quality directly.

*Expected impact:* Reducing these sellers' late rate from 22.65% to the marketplace average of 8.11% would prevent approximately **370 late orders per period**, and based on delay-vs-review analysis (Query 6.3), **~200 poor reviews**.

**Recommendation 2 — Investigate Rio de Janeiro logistics**

*Evidence:* Query 6.4 — RJ has 12,350 delivered orders with a 13.47% late rate and 1,664 late orders, 2.29× São Paulo's rate (5.89%).

*Action:* RJ-specific last-mile audit. Determine whether the problem is (a) carrier coverage, (b) warehouse-to-customer distance, or (c) regional traffic/address issues.

*Expected impact:* RJ accounts for 1,664 late orders — the second-largest absolute late-order count. Fixing RJ alone could reduce marketplace late rate by ~0.5–1 percentage point.

**Recommendation 3 — Target a 4-day maximum delivery delay**

*Evidence:* Query 6.3 — Review scores collapse between the 1–3 day bucket (3.29) and the 4–7 day bucket (2.10). Beyond 4 days, satisfaction is unrecoverable (75.58% poor reviews).

*Action:* Set an operational KPI: "No order should ship past day 3 of lateness without customer notification and compensation."

*Expected impact:* Even if late orders can't be prevented, proactive intervention could move them from "poor review" to "neutral review" behavior.

**Recommendation 4 — Reframe retention as a delivery problem**

*Evidence:* Query 5.4 — Retention is flat across all customer value bands (2.56%–3.53%). Query 6.3 — Late delivery strongly drives poor reviews.

*Action:* Treat late delivery not just as an operational metric but as a **retention driver**. Measure retention separately for customers who experienced a late delivery vs. those who didn't.

*Expected impact:* Shifting retention from 3.05% (Query 5.2) to even 5% would add **~1,860 additional repeat customers**, worth an estimated **R$577K+ in incremental GMV** (at R$310.49 avg repeat customer value, Query 5.5).

**Recommendation 5 — Implement two-dimensional seller risk scoring**

*Evidence:* Query 7.5 — Sellers with high poor-review rates but normal late rates would be missed by late-rate-only filters. Example: `7c67e144…` (R$237K GMV, 13.37% late, 29.35% poor reviews).

*Action:* Score sellers on two dimensions: (1) late rate, (2) poor review rate. Any seller in the top decile of either dimension, with meaningful GMV, should receive intervention.

*Expected impact:* Catches quality failures that pure logistics monitoring would miss.

---

## summary — Data Quality

| Check | Result | Status |
|---|---|---|
| Total orders in raw = total orders in transformed | 99,441 = 99,441 | PASS |
| Orders without items | 775 (mostly unavailable/canceled) | Expected |
| Orphan orders (FK to customers) | 0 | PASS |
| Orphan order items (FK to orders/products/sellers) | 0 | PASS |
| Duplicate order_ids | 0 | PASS |
| Orders with multiple reviews | 547 | Documented |
| Delivered orders missing delivery date | 31 | Documented |
| Delivered orders with reviews | 95,831 / 96,478 (99.33%) | High coverage |

---
