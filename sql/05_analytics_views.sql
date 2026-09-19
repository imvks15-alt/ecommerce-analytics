/* ==========================================================================
   OLIST E-COMMERCE — ANALYTICAL VIEWS
   
   Purpose: Pre-computed reusable views used by Power BI.
   
   Views:
     1. vw_order_analysis      — 1 row per order with delivery and value metrics
     2. vw_seller_performance  — 1 row per seller with GMV, late rate, review metrics
     3. vw_category_performance — 1 row per category with GMV, late rate, review metrics
     4. vw_monthly_sales        — 1 row per purchase-month with sales KPIs
   
   Design notes:
   - Reviews are pre-aggregated to order grain in seller/category views
     to prevent row multiplication (547 orders have multiple reviews)
   - Each view has its own grain — no accidental joins across grains
   ========================================================================== */


-- ==========================================================================
-- ORDER ANALYSIS VIEW
-- ==========================================================================

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

    -- Delivery metrics
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
    DATEDIFF(o.order_estimated_delivery_date, o.order_purchase_timestamp) AS estimated_delivery_days,
    DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS delivery_delay_days,

    -- Flags
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN 1 ELSE 0
    END AS is_late,

    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
        THEN 1 ELSE 0
    END AS is_delivered,

    -- Delay bucket (business-friendly label)
    CASE
        WHEN o.order_delivered_customer_date IS NULL
          OR o.order_estimated_delivery_date IS NULL
        THEN 'Not delivered / Unknown'

        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) <= 0
        THEN 'On Time / Early'

        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 1 AND 3
        THEN '1-3 days late'

        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 4 AND 7
        THEN '4-7 days late'

        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) BETWEEN 8 AND 14
        THEN '8-14 days late'

        ELSE '15+ days late'
    END AS delay_bucket,

    -- REVIEW DATA (added)
    rev.review_score,
    IF(rev.review_score <= 2, 1, 0 ) AS is_poor_review,

    -- Order value (aggregated from order items)
    oi_agg.product_value,
    oi_agg.freight_value,
    oi_agg.order_value,
    oi_agg.item_count

FROM olist_orders o

LEFT JOIN olist_customers c
    ON o.customer_id = c.customer_id

LEFT JOIN (
    SELECT 
        order_id, 
        AVG(review_score) AS review_score
    FROM olist_order_reviews
    GROUP BY order_id
) rev 
    ON o.order_id = rev.order_id

LEFT JOIN (
    SELECT
        order_id,
        ROUND(SUM(price), 2) AS product_value,
        ROUND(SUM(freight_value), 2) AS freight_value,
        ROUND(SUM(price + freight_value), 2) AS order_value,
        COUNT(*) AS item_count
    FROM olist_order_items
    GROUP BY order_id
) oi_agg
    ON o.order_id = oi_agg.order_id;
    


-- ==========================================================================
-- SELLER PERFORMANCE VIEW
-- ==========================================================================

DROP VIEW IF EXISTS vw_seller_performance;

CREATE VIEW vw_seller_performance AS

SELECT
    s.seller_id,
    s.seller_state,
    s.seller_city,

    -- Volume
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(*) AS item_rows,

    -- Value
    ROUND(SUM(oi.price), 2) AS product_gmv,
    ROUND(SUM(oi.freight_value), 2) AS freight_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS seller_gmv,

    -- Delivery
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1)
        AS avg_delivery_days,

    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
             THEN 1 ELSE 0 END) AS late_orders,

    ROUND(
        100.0 * SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
                         THEN 1 ELSE 0 END)
        / NULLIF(COUNT(DISTINCT o.order_id), 0),
        2
    ) AS late_rate_pct,

    -- Reviews (joined at order grain to avoid multiplication)
    ROUND(AVG(rev.review_score), 2) AS avg_review_score,

    ROUND(
        100.0 * SUM(CASE WHEN rev.review_score <= 2 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(rev.review_score), 0),
        2
    ) AS poor_review_rate_pct

FROM olist_order_items oi

JOIN olist_orders o
    ON oi.order_id = o.order_id

JOIN olist_sellers s
    ON oi.seller_id = s.seller_id

-- Pre-aggregate reviews per order to avoid item × review multiplication
LEFT JOIN (
    SELECT
        order_id,
        AVG(review_score) AS review_score
    FROM olist_order_reviews
    GROUP BY order_id
) rev
    ON o.order_id = rev.order_id

WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL

GROUP BY
    s.seller_id,
    s.seller_state,
    s.seller_city;


-- ==========================================================================
-- CATEGORY PERFORMANCE VIEW
-- ==========================================================================

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


-- ==========================================================================
-- MONTHLY SALES VIEW
-- ==========================================================================

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