/* ==========================================================================
   OLIST ANALYTICS — COMPLETE SQL QUERY LOG
   Purpose: Reference of all analytical SQL used in the analysis,
            organized chronologically with findings and business context.
   ========================================================================== */


-- ==========================================================================
-- SALES
-- ==========================================================================

-- 1.1 — Dataset Date Range
-- Purpose: Establish the analytical window — first and last order dates,
--          total order count.

SELECT
    MIN(order_purchase_timestamp) AS first_order_date,
    MAX(order_purchase_timestamp) AS last_order_date,
    COUNT(DISTINCT order_id) AS total_orders
FROM olist_orders;
-- Result: 2016-09-04 → 2018-10-17 | 99,441 orders


-- 1.2 — Overall Sales
-- Purpose: Get marketplace metrics — orders, customers,
--          product value, freight, total order value.

SELECT
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    ROUND(SUM(oi.price), 2) AS product_revenue,
    ROUND(SUM(oi.freight_value), 2) AS freight_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_order_value
FROM olist_order_items oi
JOIN olist_orders o
    ON oi.order_id = o.order_id
JOIN olist_customers c
    ON o.customer_id = c.customer_id;
-- Result: 98,666 orders / 95,420 customers / R$13,591,643.70 product /
--         R$2,251,909.54 freight / R$15,843,553.24 total
-- Note: 99,441 orders exist but only 98,666 have order-item records.


-- 1.3 — Order Status Distribution
-- Purpose: Understand the composition of the order base — how many are
--          delivered vs other statuses.

SELECT
    order_status,
    COUNT(DISTINCT order_id) AS orders
FROM olist_orders
GROUP BY order_status
ORDER BY orders DESC;
-- Result: delivered 96,478 | shipped 1,107 | canceled 625 |
--         unavailable 609 | invoiced 314 | processing 301 |
--         created 5 | approved 2


-- 1.4 — Orders Without Items (Investigation)
-- Purpose: Investigate the 775-order gap between total orders and
--          orders-with-items — by status.

SELECT
    o.order_status,
    COUNT(*) AS orders_without_items
FROM olist_orders o
LEFT JOIN olist_order_items oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;
-- Result: unavailable 603 | canceled 164 | created 5 | invoiced 2 | shipped 1
-- Insight: Missing items are concentrated in unavailable/canceled orders —
--          not a data quality issue.


-- 1.5 — Financials by Order Status
-- Purpose: Compute revenue breakdown by lifecycle status to decide which
--          population to use for "sales".

SELECT
    o.order_status,
    COUNT(DISTINCT o.order_id) AS orders,
    COUNT(DISTINCT CASE
        WHEN oi.order_id IS NOT NULL THEN o.order_id
    END) AS orders_with_items,
    ROUND(SUM(oi.price), 2) AS product_value,
    ROUND(SUM(oi.freight_value), 2) AS freight_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS order_value
FROM olist_orders o
LEFT JOIN olist_order_items oi
    ON o.order_id = oi.order_id
GROUP BY o.order_status
ORDER BY orders DESC;
-- Result: Delivered R$15.42M | shipped R$177K | canceled R$106K |
--         unavailable R$2K | invoiced R$69K | processing R$69K |
--         approved R$241


-- 1.6 — Delivered Order Economics
-- Purpose: Establish the delivered-order revenue baseline used as the
--          primary "sales" population.

SELECT
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(SUM(oi.price), 2) AS delivered_product_value,
    ROUND(SUM(oi.freight_value), 2) AS delivered_freight_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS delivered_order_value
FROM olist_orders o
JOIN olist_order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered';
-- Result: 96,478 orders | R$13,221,498.11 product | R$2,198,275.64 freight |
--         R$15,419,773.75 total


-- 1.7 — Delivered AOV (Correct Grain)
-- Purpose: Calculate AOV correctly — at order grain, not item grain.
--          Aggregates items per order first.

SELECT
    COUNT(*) AS delivered_orders,
    ROUND(SUM(order_value), 2) AS delivered_order_value,
    ROUND(SUM(order_value) / COUNT(*), 2) AS delivered_aov
FROM (
    SELECT
        o.order_id,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM olist_orders o
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
) x;
-- Result: 96,478 orders | R$15,419,773.75 | AOV = R$159.83


-- ==========================================================================
-- MONTHLY SALES TREND
-- ==========================================================================

-- 2.1 — Monthly Delivered Sales
-- Purpose: First monthly trend cut — delivered orders, unique customers,
--          order value, AOV by month.

SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(*) AS delivered_orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    ROUND(SUM(x.order_value), 2) AS delivered_order_value,
    ROUND(SUM(x.order_value) / COUNT(*), 2) AS aov
FROM olist_orders o
JOIN (
    SELECT
        order_id,
        SUM(price + freight_value) AS order_value
    FROM olist_order_items
    GROUP BY order_id
) x
    ON o.order_id = x.order_id
JOIN olist_customers c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;
-- Insight: Result stopped at 2018-08 — flagged an analytical issue with
--          using delivered-status for sales timing.


-- 2.2 — Last-Month Status Check
-- Purpose: Investigate why Sep/Oct 2018 were missing from delivered analysis.

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,
    order_status,
    COUNT(*) AS orders
FROM olist_orders
WHERE order_purchase_timestamp >= '2018-08-01'
GROUP BY
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m'),
    order_status
ORDER BY
    order_month,
    order_status;
-- Result: Sep 2018 = 1 shipped + 15 canceled | Oct 2018 = 4 canceled.
--         No delivered orders.


-- 2.3 — Sales Trend (Corrected — Purchase Date Grain)
-- Purpose: Rebuild the sales trend using purchase date (not delivery status)
--          to properly measure sales timing.

SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(DISTINCT o.order_id) AS orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    ROUND(SUM(oi.price), 2) AS product_value,
    ROUND(SUM(oi.freight_value), 2) AS freight_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS order_value
FROM olist_orders o
JOIN olist_order_items oi
    ON o.order_id = oi.order_id
JOIN olist_customers c
    ON o.customer_id = c.customer_id
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY order_month;
-- Insight: Now covers Sep 2016 → Sep 2018. Confirmed the "sales" population
--          should be purchase-date based.


-- 2.4 — Monthly AOV (Order-Grain Aggregation)
-- Purpose: Recompute monthly AOV using correct order-grain aggregation.

SELECT
    order_month,
    COUNT(*) AS orders,
    COUNT(DISTINCT customer_unique_id) AS unique_customers,
    ROUND(SUM(order_value), 2) AS order_value,
    ROUND(SUM(order_value) / COUNT(*), 2) AS aov
FROM (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        o.order_id,
        c.customer_unique_id,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM olist_orders o
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    GROUP BY
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m'),
        o.order_id,
        c.customer_unique_id
) x
GROUP BY order_month
ORDER BY order_month;


-- 2.5 — Month-over-Month Growth
-- Purpose: Calculate MoM growth in orders, order value, and AOV using
--          window functions.

WITH monthly_sales AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        COUNT(DISTINCT o.order_id) AS orders,
        COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM olist_orders o
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
),
monthly_metrics AS (
    SELECT
        order_month,
        orders,
        unique_customers,
        order_value,
        order_value / orders AS aov,
        LAG(orders) OVER (ORDER BY order_month) AS previous_orders,
        LAG(order_value) OVER (ORDER BY order_month) AS previous_order_value,
        LAG(order_value / orders) OVER (ORDER BY order_month) AS previous_aov
    FROM monthly_sales
)
SELECT
    order_month,
    orders,
    unique_customers,
    ROUND(order_value, 2) AS order_value,
    ROUND(aov, 2) AS aov,
    ROUND(100.0 * (orders - previous_orders) / NULLIF(previous_orders, 0), 2) AS mom_orders_growth_pct,
    ROUND(100.0 * (order_value - previous_order_value) / NULLIF(previous_order_value, 0), 2) AS mom_order_value_growth_pct,
    ROUND(100.0 * (aov - previous_aov) / NULLIF(previous_aov, 0), 2) AS mom_aov_growth_pct
FROM monthly_metrics
ORDER BY order_month;
-- Insight: Identified the Nov 2017 spike (+53.27% MoM order value).


-- ==========================================================================
-- NOVEMBER 2017 SPIKE DIAGNOSIS
-- ==========================================================================

-- 3.1 — Oct vs Nov Order-Level Decomposition
-- Purpose: Break down the Nov spike into orders, customers, product value,
--          freight, AOV, items/order.

WITH order_level AS (
    SELECT
        o.order_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        c.customer_unique_id,
        SUM(oi.price) AS product_value,
        SUM(oi.freight_value) AS freight_value,
        SUM(oi.price + oi.freight_value) AS order_value,
        COUNT(*) AS item_count
    FROM olist_orders o
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    WHERE o.order_purchase_timestamp >= '2017-10-01'
      AND o.order_purchase_timestamp < '2017-12-01'
    GROUP BY
        o.order_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m'),
        c.customer_unique_id
)
SELECT
    order_month,
    COUNT(*) AS orders,
    COUNT(DISTINCT customer_unique_id) AS customers,
    ROUND(SUM(product_value), 2) AS product_value,
    ROUND(SUM(freight_value), 2) AS freight_value,
    ROUND(SUM(order_value), 2) AS order_value,
    ROUND(AVG(order_value), 2) AS aov,
    ROUND(AVG(item_count), 2) AS avg_items_per_order
FROM order_level
GROUP BY order_month
ORDER BY order_month;
-- Result: Oct→Nov: orders +63.11%, value +53.27%, AOV −6.03%, items/order flat.
-- Insight: Volume-driven, not basket-size-driven.


-- 3.2 — New vs Existing Customers (Nov 2017)
-- Purpose: Determine whether the Nov customer surge was new acquisition
--          or repeat purchasing.

WITH first_purchase AS (
    SELECT
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_order_date
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
),
november_orders AS (
    SELECT
        o.order_id,
        c.customer_unique_id,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_purchase_timestamp >= '2017-11-01'
      AND o.order_purchase_timestamp < '2017-12-01'
    GROUP BY o.order_id, c.customer_unique_id
)
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
JOIN first_purchase fp
    ON no.customer_unique_id = fp.customer_unique_id
GROUP BY customer_type;
-- Result: New 7,216 customers (98.3%) | Existing 126 |
--         New drove R$1.16M of R$1.18M total.


-- ==========================================================================
-- CUSTOMER RETENTION
-- ==========================================================================

-- 4.1 — Repeat Customer Rate
-- Purpose: First-pass repeat customer metric.

WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN order_count = 1 THEN 1 ELSE 0 END) AS one_time_customers,
    SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_customer_rate
FROM customer_orders;
-- Result: 95,420 customers | 92,507 one-time | 2,913 repeat | 3.05%


-- 4.2 — Purchase Frequency Distribution
-- Purpose: See how orders-per-customer is distributed — not just the rate.

WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
)
SELECT
    order_count,
    COUNT(*) AS customers
FROM customer_orders
GROUP BY order_count
ORDER BY order_count;
-- Result: 1 order → 92,507 | 2 → 2,673 | 3 → 192 | 4 → 29 | 5 → 9 |
--         6 → 5 | 7 → 3 | 9 → 1 | 16 → 1


-- 4.3 — One-Time vs Repeat Customer Value
-- Purpose: Compare economic value of one-time vs repeat customers.

WITH customer_order_counts AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
),
customer_value AS (
    SELECT
        c.customer_unique_id,
        SUM(oi.price + oi.freight_value) AS order_value
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
)
SELECT
    CASE
        WHEN coc.order_count = 1 THEN 'One-time Customer'
        ELSE 'Repeat Customer'
    END AS customer_type,
    COUNT(*) AS customers,
    ROUND(SUM(cv.order_value), 2) AS total_order_value,
    ROUND(AVG(cv.order_value), 2) AS avg_customer_value
FROM customer_order_counts coc
JOIN customer_value cv
    ON coc.customer_unique_id = cv.customer_unique_id
GROUP BY customer_type;
-- Result: One-time R$161.49 avg | Repeat R$310.49 avg | 1.92× ratio


-- 4.4 — Time to Second Order
-- Purpose: Calculate average days between first and second order.

WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY o.order_purchase_timestamp
        ) AS order_number
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
),
first_second AS (
    SELECT
        customer_unique_id,
        MAX(CASE WHEN order_number = 1 THEN order_purchase_timestamp END) AS first_order_date,
        MAX(CASE WHEN order_number = 2 THEN order_purchase_timestamp END) AS second_order_date
    FROM customer_orders
    WHERE order_number <= 2
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS repeat_customers,
    ROUND(AVG(DATEDIFF(second_order_date, first_order_date)), 1) AS avg_days_to_second_order,
    MIN(DATEDIFF(second_order_date, first_order_date)) AS min_days,
    MAX(DATEDIFF(second_order_date, first_order_date)) AS max_days
FROM first_second
WHERE second_order_date IS NOT NULL;
-- Incorrect Result: 11,869 | 17.4 | 0 | 609
-- Issue: Uses ROW_NUMBER() before deduplicating to order grain.
--        Join to olist_order_items multiplies rows per customer.
--        Overcounts repeat customers (11,869 instead of 2,913).


-- 4.5 — Control Query (Retention Reconciliation)
-- Purpose: Reconcile the retention count discrepancy. 
--          Uses SELECT DISTINCT before aggregation.
WITH customer_orders AS (
    SELECT DISTINCT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
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
    ROUND(100.0 * SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM customer_order_counts;
-- Result: 95,420 | 92,507 | 2,913 | 3.05%  -> Confirms the correct population


-- 4.6 — Days to Second Order (CORRECTED)
-- Purpose: Correct version of 4.4 — deduplicates to order grain BEFORE
--          ROW_NUMBER().

WITH customer_orders AS (
    SELECT DISTINCT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
),
ranked AS (
    SELECT
        customer_unique_id,
        order_id,
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
    COUNT(*) AS repeat_customers,
    ROUND(AVG(DATEDIFF(second_order_date, first_order_date)), 1) AS avg_days_to_second_order,
    MIN(DATEDIFF(second_order_date, first_order_date)) AS min_days,
    MAX(DATEDIFF(second_order_date, first_order_date)) AS max_days,
    ROUND(STDDEV(DATEDIFF(second_order_date, first_order_date)), 1) AS stddev_days
FROM first_second
WHERE second_order_date IS NOT NULL;
-- Result: 2,913 | 80.8 | 0 | 609 | 110.2 


-- 4.7 — Return Buckets
-- Purpose: Bucket the return interval.

WITH customer_orders AS (
    SELECT DISTINCT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
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
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS customer_share_pct
FROM return_days
GROUP BY return_bucket
ORDER BY MIN(days_to_second_order);
-- Result: 0 days 875 (30.04%) | 1-30 603 | 31-60 313 | 61-90 201 |
--         91-180 424 | 181-365 411 | 365+ 86


-- 4.8 — Retention by First-Order Value
-- Purpose: whether retention differs by customer value segment.

WITH first_order AS (
    SELECT
        c.customer_unique_id,
        MIN(o.order_purchase_timestamp) AS first_order_date
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    GROUP BY c.customer_unique_id
),
first_order_value AS (
    SELECT
        fo.customer_unique_id,
        SUM(oi.price + oi.freight_value) AS first_order_value
    FROM first_order fo
    JOIN olist_orders o
        ON o.order_purchase_timestamp = fo.first_order_date
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
       AND c.customer_unique_id = fo.customer_unique_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
    GROUP BY fo.customer_unique_id
),
customer_counts AS (
    SELECT DISTINCT
        c.customer_unique_id,
        o.order_id
    FROM olist_orders o
    JOIN olist_customers c
        ON o.customer_id = c.customer_id
    JOIN olist_order_items oi
        ON o.order_id = oi.order_id
),
customer_orders AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS order_count
    FROM customer_counts
    GROUP BY customer_unique_id
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
JOIN customer_orders co
    ON fov.customer_unique_id = co.customer_unique_id
GROUP BY first_order_value_band
ORDER BY first_order_value_band;
-- Result: 3.05% | 2.89% | 3.03% | 3.53% | 2.56% — flat across bands


-- ==========================================================================
-- DELIVERY PERFORMANCE
-- ==========================================================================

-- 5.1 — Delivery Baseline
-- Purpose: Establish the delivery performance baseline — avg days, delay,
--          late rate.

SELECT
    COUNT(*) AS delivered_orders,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(AVG(DATEDIFF(order_estimated_delivery_date, order_purchase_timestamp)), 1) AS avg_estimated_days,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date)), 1) AS avg_delay_days,
    SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_rate_pct
FROM olist_orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;
-- Result: 96,447 | 12.5 | 24.4 | −11.9 | 7,826 | 8.11%


-- 5.2 — Review Grain Check
-- Purpose: Verify whether reviews are 1:1 with orders before joining to
--          delivery analysis.

SELECT
    COUNT(*) AS total_reviews,
    COUNT(DISTINCT order_id) AS unique_orders_reviewed,
    COUNT(DISTINCT review_id) AS unique_review_ids
FROM olist_order_reviews;
-- Result: 99,223 | 98,672 | 98,409 — not 1:1 (551 orders have multiple reviews)


-- 5.3 — Delay vs Review Score (The Money Shot)
-- Purpose: Test whether late delivery is associated with lower review scores.

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
    ROUND(100.0 * SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) / COUNT(DISTINCT o.order_id), 2) AS poor_review_rate_pct
FROM olist_orders o
JOIN olist_order_reviews r
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY delay_bucket
ORDER BY delay_bucket;
-- Result: 4.29 → 3.29 → 2.10 → 1.68 → 1.72 across buckets.
-- The project's headline finding.


-- 5.4 — Late Rate by Customer State
-- Purpose: Geographic root cause — which states have the worst late rates.

SELECT
    c.customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date)), 1) AS avg_delay_days,
    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_rate_pct
FROM olist_orders o
JOIN olist_customers c
    ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(*) >= 100
ORDER BY late_rate_pct DESC;
-- Result: AL 23.93% | MA 19.67% | PI 15.97% | CE 15.32% | ... |
--         RJ 13.47% (12,349 orders) | SP 5.90%


-- 5.5 — Late Rate by Seller (Top 30)
-- Purpose: Identify sellers with worst late rates (min 30 orders).

SELECT
    s.seller_id,
    s.seller_state,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS seller_gmv,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(DISTINCT o.order_id), 2) AS late_rate_pct
FROM olist_order_items oi
JOIN olist_orders o
    ON oi.order_id = o.order_id
JOIN olist_sellers s
    ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY s.seller_id, s.seller_state
HAVING COUNT(DISTINCT o.order_id) >= 30
ORDER BY late_rate_pct DESC
LIMIT 30;
-- Result: Top seller 37.21% late rate.
-- List dominated by SP-based sellers but mostly small volume.


-- 5.6 — High-Revenue + High-Late-Rate Sellers
-- Purpose: Filter the seller list to high-value sellers with elevated late
--          rates (top 100 by GMV, late ≥ 15%).

WITH seller_perf AS (
    SELECT
        s.seller_id,
        s.seller_state,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS seller_gmv,
        SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
        ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(DISTINCT o.order_id), 2) AS late_rate_pct
    FROM olist_order_items oi
    JOIN olist_orders o ON oi.order_id = o.order_id
    JOIN olist_sellers s ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY s.seller_id, s.seller_state
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (ORDER BY seller_gmv DESC) AS revenue_rank
    FROM seller_perf
)
SELECT
    seller_id, seller_state, delivered_orders, seller_gmv, revenue_rank, late_orders, late_rate_pct
FROM ranked
WHERE revenue_rank <= 100
  AND late_rate_pct >= 15
ORDER BY seller_gmv DESC;
-- Result: 7 sellers identified as initial priority list.


-- 5.7 — Late Rate by Product Category
-- Purpose: Test whether product category drives delivery performance.

SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS category_gmv,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(DISTINCT o.order_id), 2) AS late_rate_pct
FROM olist_order_items oi
JOIN olist_orders o ON oi.order_id = o.order_id
JOIN olist_products p ON oi.product_id = p.product_id
LEFT JOIN olist_product_category_name_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY COALESCE(t.product_category_name_english, p.product_category_name, 'unknown')
HAVING COUNT(DISTINCT o.order_id) >= 100
ORDER BY late_rate_pct DESC;
-- Result: Narrow range 8–14%. office_furniture worst (11.89%, 20.8 days avg).
-- Insight: Category is a weak driver.
-- Also discovered \r artifacts in category names.


-- 5.8 — Freight vs Lateness
-- Purpose: Test whether higher freight (proxy for distance/weight)
--          correlates with worse delivery.

WITH order_level AS (
    SELECT
        o.order_id,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        o.order_purchase_timestamp,
        SUM(oi.freight_value) AS freight_value,
        SUM(oi.price) AS product_value
    FROM olist_orders o
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_estimated_delivery_date IS NOT NULL
    GROUP BY o.order_id, o.order_delivered_customer_date, o.order_estimated_delivery_date, o.order_purchase_timestamp
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
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(AVG(DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date)), 1) AS avg_delay_days,
    ROUND(100.0 * SUM(CASE WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_rate_pct,
    ROUND(100.0 * AVG(freight_value) / NULLIF(AVG(product_value), 0), 2) AS freight_to_product_pct
FROM order_level
GROUP BY freight_band
ORDER BY freight_band;
-- Result: Monotonic 6.22% → 11.13% across freight bands.
-- Estimate algorithm adjusts for freight (delay stable at −12 to −13).


-- 5.9 — Seller Risk Scorecard
-- Purpose: Combine GMV + late rate + review metrics + risk segmentation
--          into a single actionable seller table.

WITH seller_delivery AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS seller_gmv,
        SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
        ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) / COUNT(DISTINCT o.order_id), 2) AS late_rate_pct
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
        SUM(CASE WHEN r.review_score <= 2 THEN 1 ELSE 0 END) AS poor_reviews,
        COUNT(DISTINCT o.order_id) AS reviewed_orders
    FROM olist_order_items oi
    JOIN olist_orders o ON oi.order_id = o.order_id
    JOIN olist_order_reviews r ON o.order_id = r.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
),
seller_combined AS (
    SELECT
        d.seller_id,
        s.seller_state,
        d.delivered_orders,
        d.seller_gmv,
        d.late_orders,
        d.late_rate_pct,
        r.avg_review_score,
        ROUND(100.0 * r.poor_reviews / NULLIF(r.reviewed_orders, 0), 2) AS poor_review_rate_pct
    FROM seller_delivery d
    LEFT JOIN seller_reviews r ON d.seller_id = r.seller_id
    LEFT JOIN olist_sellers s ON d.seller_id = s.seller_id
)
SELECT
    seller_id, seller_state, delivered_orders, seller_gmv,
    late_orders, late_rate_pct, avg_review_score, poor_review_rate_pct,
    CASE
        WHEN seller_gmv >= 20000 AND late_rate_pct >= 15 THEN 'Priority Intervention'
        WHEN seller_gmv >= 20000 AND late_rate_pct >= 10 THEN 'Monitor'
        WHEN seller_gmv < 20000 AND late_rate_pct >= 20 THEN 'Investigate'
        ELSE 'Healthy'
    END AS risk_segment
FROM seller_combined
WHERE delivered_orders >= 30
ORDER BY 
    CASE
        WHEN seller_gmv >= 20000 AND late_rate_pct >= 15 THEN 1
        WHEN seller_gmv >= 20000 AND late_rate_pct >= 10 THEN 2
        WHEN seller_gmv < 20000 AND late_rate_pct >= 20 THEN 3
        ELSE 4
    END,
    seller_gmv DESC
LIMIT 50;
-- Result: 11 priority sellers identified with R$424K combined GMV.


-- ==========================================================================
-- ANALYTICAL VIEWS
-- ==========================================================================

-- 6.1 — vw_order_analysis
-- Purpose: One row per order with delivery/delay metrics + customer
--          geography + order value aggregated from items.

DROP VIEW IF EXISTS vw_order_analysis;

CREATE VIEW vw_order_analysis AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
    DATEDIFF(o.order_estimated_delivery_date, o.order_purchase_timestamp) AS estimated_delivery_days,
    DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS delivery_delay_days,
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END AS is_late,
    CASE WHEN o.order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END AS is_delivered,
    CASE
        WHEN o.order_delivered_customer_date IS NULL OR o.order_estimated_delivery_date IS NULL THEN 'Not delivered / Unknown'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) <= 0 THEN 'On Time / Early'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 1 AND 3 THEN '1-3 days late'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 4 AND 7 THEN '4-7 days late'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 8 AND 14 THEN '8-14 days late'
        ELSE '15+ days late'
    END AS delay_bucket,
    oi_agg.product_value,
    oi_agg.freight_value,
    oi_agg.order_value,
    oi_agg.item_count
FROM olist_orders o
LEFT JOIN olist_customers c ON o.customer_id = c.customer_id
LEFT JOIN (
    SELECT
        order_id,
        ROUND(SUM(price), 2) AS product_value,
        ROUND(SUM(freight_value), 2) AS freight_value,
        ROUND(SUM(price + freight_value), 2) AS order_value,
        COUNT(*) AS item_count
    FROM olist_order_items
    GROUP BY order_id
) oi_agg ON o.order_id = oi_agg.order_id;
-- Result: 99,441 rows (1 per order)


-- 6.2 — vw_seller_performance
-- Purpose: One row per seller with GMV, late rate, review metrics.
--          Pre-aggregates reviews to order grain to avoid multiplication.

DROP VIEW IF EXISTS vw_seller_performance;

CREATE VIEW vw_seller_performance AS
SELECT
    s.seller_id,
    s.seller_state,
    s.seller_city,
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(*) AS item_rows,
    ROUND(SUM(oi.price), 2) AS product_gmv,
    ROUND(SUM(oi.freight_value), 2) AS freight_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS seller_gmv,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS late_rate_pct,
    ROUND(AVG(rev.review_score), 2) AS avg_review_score,
    ROUND(100.0 * SUM(CASE WHEN rev.review_score <= 2 THEN 1 ELSE 0 END) / NULLIF(COUNT(rev.review_score), 0), 2) AS poor_review_rate_pct
FROM olist_order_items oi
JOIN olist_orders o ON oi.order_id = o.order_id
JOIN olist_sellers s ON oi.seller_id = s.seller_id
LEFT JOIN (
    SELECT order_id, AVG(review_score) AS review_score
    FROM olist_order_reviews
    GROUP BY order_id
) rev ON o.order_id = rev.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY s.seller_id, s.seller_state, s.seller_city;
-- Result: 2,968 sellers


-- 6.3 — vw_category_performance
-- Purpose: One row per category.

DROP VIEW IF EXISTS vw_category_performance;

CREATE VIEW vw_category_performance AS
SELECT
    COALESCE(
        t.product_category_name_english,
        p.product_category_name,
        'unknown') AS category,
        
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(*) AS item_rows,
    ROUND(SUM(oi.price), 2) AS product_gmv,
    ROUND(SUM(oi.freight_value), 2) AS freight_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS category_gmv,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS late_rate_pct,
    ROUND(AVG(rev.review_score), 2) AS avg_review_score,
    ROUND(100.0 * SUM(CASE WHEN rev.review_score <= 2 THEN 1 ELSE 0 END) / NULLIF(COUNT(rev.review_score), 0), 2) AS poor_review_rate_pct
FROM olist_order_items oi
JOIN olist_orders o ON oi.order_id = o.order_id
JOIN olist_products p ON oi.product_id = p.product_id
LEFT JOIN olist_product_category_name_translation t ON p.product_category_name = t.product_category_name
LEFT JOIN (
    SELECT order_id, AVG(review_score) AS review_score
    FROM olist_order_reviews
    GROUP BY order_id
) rev ON o.order_id = rev.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY category;
-- Result: 74 categories


-- 6.4 — vw_monthly_sales
-- Purpose: One row per purchase-month with orders, customers, GMV, AOV,
--          items/order.

DROP VIEW IF EXISTS vw_monthly_sales;

CREATE VIEW vw_monthly_sales AS
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
    COUNT(DISTINCT o.order_id) AS orders,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    COUNT(*) AS item_rows,
    ROUND(SUM(oi.price), 2) AS product_value,
    ROUND(SUM(oi.freight_value), 2) AS freight_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS order_value,
    ROUND(SUM(oi.price + oi.freight_value) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS aov,
    ROUND(COUNT(*) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS items_per_order
FROM olist_orders o
JOIN olist_order_items oi ON o.order_id = oi.order_id
JOIN olist_customers c ON o.customer_id = c.customer_id
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m');
-- Result: 24 months


-- ==========================================================================
-- VERIFICATION & CONFIRMATION QUERIES
-- ==========================================================================

-- 7.1 — Delivered Orders Reconciliation
-- Purpose: Explain the 96,478 vs 96,447 discrepancy.

SELECT
    COUNT(*) AS total_delivered_orders,
    SUM(CASE WHEN order_delivered_customer_date IS NOT NULL AND order_estimated_delivery_date IS NOT NULL THEN 1 ELSE 0 END) AS delivered_with_both_dates,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS missing_actual_delivery_date,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS missing_estimated_delivery_date,
    SUM(CASE WHEN order_delivered_customer_date IS NULL OR order_estimated_delivery_date IS NULL THEN 1 ELSE 0 END) AS delivered_missing_either_date
FROM olist_orders
WHERE order_status = 'delivered';
-- Result: 96,478 | 96,447 | 31 | 0 | 31


-- 7.2 — Delivered AOV Exact
-- Purpose: Extract the exact AOV + distribution context.

SELECT
    COUNT(*) AS delivered_orders,
    ROUND(SUM(order_value), 2) AS delivered_order_value,
    ROUND(SUM(order_value) / COUNT(*), 2) AS delivered_aov,
    ROUND(AVG(order_value), 2) AS delivered_aov_check,
    ROUND(MIN(order_value), 2) AS min_order_value,
    ROUND(MAX(order_value), 2) AS max_order_value,
    ROUND(STDDEV(order_value), 2) AS stddev_order_value
FROM (
    SELECT o.order_id, SUM(oi.price + oi.freight_value) AS order_value
    FROM olist_orders o
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id
) x;
-- Result: 96,478 | R$15,419,773.75 | R$159.83 | R$159.83 | R$9.59 |
--         R$13,664.08 | R$218.79


-- 7.3 — GMV at Risk (Priority Sellers Exact)
-- Purpose: Confirmed priority seller count and total GMV from the view.

SELECT
    COUNT(*) AS priority_sellers,
    SUM(seller_gmv) AS total_gmv_at_risk,
    SUM(delivered_orders) AS total_orders,
    SUM(late_orders) AS total_late_orders,
    ROUND(AVG(late_rate_pct), 2) AS avg_late_rate,
    ROUND(AVG(avg_review_score), 2) AS avg_review_score,
    ROUND(AVG(poor_review_rate_pct), 2) AS avg_poor_review_rate
FROM vw_seller_performance
WHERE seller_gmv >= 20000 AND late_rate_pct >= 15;
-- Result: 15 | R$518,557.64 | 2,552 | 499 | 22.65% | 3.56 | 29.03%
-- Note: Returned 15, not 11 — because vw_seller_performance includes all
--       sellers (not just top 100).


-- 7.4 — Marketplace Review Baselines
-- Purpose: Baseline review metrics for comparison with sellers/categories.

SELECT
    COUNT(*) AS total_reviews,
    ROUND(AVG(review_score), 2) AS avg_review_score,
    SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS poor_reviews,
    ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS poor_review_rate_pct,
    SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END) AS five_star_reviews,
    ROUND(100.0 * SUM(CASE WHEN review_score = 5 THEN 1 ELSE 0 END) / COUNT(*), 2) AS five_star_rate_pct
FROM olist_order_reviews;
-- Result: 99,223 | 4.09 | 14,575 | 14.69% | 57,327 | 57.78%


-- 7.5 — Review Grain Duplicates
-- Purpose: Quantify multi-review orders for the limitations section.

SELECT
    COUNT(*) AS orders_with_multiple_reviews,
    SUM(review_count) AS total_rows_for_these_orders,
    ROUND(AVG(review_count), 2) AS avg_reviews_per_duplicated_order,
    MAX(review_count) AS max_reviews_per_order
FROM (
    SELECT order_id, COUNT(*) AS review_count
    FROM olist_order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x;
-- Result: 547 | 1,098 | 2.01 | 3


-- 7.6 — Delivered Review Coverage
-- Purpose: True review coverage on delivered orders (replacing the broken
--          102.27% figure).

SELECT
    COUNT(DISTINCT r.order_id) AS delivered_orders_with_reviews,
    (SELECT COUNT(*) FROM olist_orders WHERE order_status = 'delivered') AS delivered_orders,
    ROUND(
        100.0 * COUNT(DISTINCT r.order_id)
        / (SELECT COUNT(*) FROM olist_orders WHERE order_status = 'delivered'),
        2
    ) AS delivered_review_coverage_pct
FROM olist_order_reviews r
JOIN olist_orders o ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';
-- Result: 95,831 | 96,478 | 99.33%


/* ==========================================================================
   SUMMARY
   ==========================================================================
   Total queries in this log: 40 

   By phase:
     Sales		   :      7 queries
     Monthly trend:       5 queries
     Nov 2017 spike:      2 queries
     Retention:           9 queries 
     Delivery:            9 queries
     Views:               4 CREATE VIEW statements
     Verification:        6 confirmation queries

   Documented corrections:
     1. Sales trend       — delivered-date → purchase-date
     2. AOV               — item grain → order grain
     3. Retention         — ROW_NUMBER before dedup → SELECT DISTINCT before ROW_NUMBER
   ========================================================================== */