/* ==========================================================
E-COMMERCE DATA VALIDATION REPORT
DATA & BUSINESS RULE VALIDATION
========================================================== */

/* Purpose: Identify data quality issues and business rule violations
            in the raw staging data BEFORE transformation.

NOTES:-
  All staging columns were ingested as VARCHAR.
   Therefore, this script does NOT assume that values are:
       - correctly typed
       - non-null
       - non-empty
       - correctly formatted
       - within valid business ranges

 VALIDATION AREAS:
   1. Row counts
   2. NULL / empty / whitespace values
   3. Duplicate business keys
   4. Invalid identifiers
   5. Invalid numeric values
   6. Invalid dates format
   7. Date chronology
   8. Invalid categorical values
   9. Invalid Brazilian state codes
  10. ZIP-code validation
  11. City/state anomalies
  12. Foreign-key/orphan checks
  13. Geographic coordinate validation
  14. Negative financial values
  15. Review-score validation
  16. Product/category validation

INTERPRETATION:
   This layer identifies DATA QUALITY ISSUES and BUSINESS RULES VOILATIONS.
*/

USE olist_ecommerce;

/* ==========================================================
CUSTOMERS
Table Name: staging_customers
========================================================== */

-- staging_customers: empty string check
SELECT
SUM(TRIM(customer_id) = '') AS customer_id_empty,
SUM(TRIM(customer_unique_id) = '') AS customer_unique_id_empty,
SUM(TRIM(customer_zip_code_prefix) = '') AS zip_code_empty,
SUM(TRIM(customer_city) = '') AS city_empty,
SUM(TRIM(customer_state) = '') AS state_empty
FROM staging_customers;
 

-- staging_customers: format validation

SELECT
	SUM(TRIM(customer_id) <> ''
	AND TRIM(customer_id) NOT REGEXP '^[a-f0-9]{32}$')
		AS invalid_customer_id,
        
	SUM(TRIM(customer_unique_id) <> ''
	AND TRIM(customer_unique_id) NOT REGEXP '^[a-f0-9]{32}$')
		AS invalid_customer_unique_id, 
        
    SUM(TRIM(customer_zip_code_prefix) <> ''
		AND TRIM(customer_zip_code_prefix) NOT REGEXP '^[0-9]{5}$') 
			AS invalid_zip_code_format,
            
	SUM(TRIM(customer_city) <> ''
	AND TRIM(customer_city) NOT REGEXP '^[a-zA-ZÀ-ÿ]+([ -][a-zA-ZÀ-ÿ]+)*$')
		AS suspicious_customer_city,
        
	SUM(TRIM(customer_state) <> ''
		AND TRIM(customer_state) NOT REGEXP '^[A-Z]{2}$') 
			AS invalid_state_code_format
FROM staging_customers;
/* 227 customer_city values were identified by the original validation as format exceptions.
These values require review because city standardization is important for location-level analysis. */

-- staging_customers: distinct city values for city standardization review
SELECT
DISTINCT customer_city
FROM staging_customers
ORDER BY customer_city;

-- staging_customers: duplicate customer_id check
SELECT
customer_id,
COUNT(*) AS occurrences
FROM staging_customers
WHERE TRIM(customer_id) REGEXP '^[a-f0-9]{32}$'
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- staging_customers: referential integrity check -> staging_orders
SELECT
so.order_id,
so.customer_id
FROM staging_customers sc
LEFT JOIN staging_orders so
ON so.customer_id = sc.customer_id
WHERE sc.customer_id IS NULL;

/* ==========================================================
2. PRODUCTS
========================================================== */

-- staging_products: empty string check
SELECT
SUM(TRIM(product_id) = '') AS product_id_empty,
SUM(TRIM(product_category_name) = '') AS category_empty,
SUM(TRIM(product_name_length) = '') AS name_length_empty,
SUM(TRIM(product_description_length) = '') AS description_length_empty,
SUM(TRIM(product_photos_qty) = '') AS photos_qty_empty,
SUM(TRIM(product_weight_g) = '') AS weight_empty,
SUM(TRIM(product_length_cm) = '') AS length_empty,
SUM(TRIM(product_height_cm) = '') AS height_empty,
SUM(TRIM(product_width_cm) = '') AS width_empty
FROM staging_products;

/*
610 rows have missing product category, name length, description length, and photo quantity values.
2 rows have missing product dimension values.
These values should be handled according to their analytical impact rather than automatically removed.
*/


-- staging_products: numeric and identifier format validation
SELECT
    SUM(TRIM(product_id) <> ''
        AND TRIM(product_id) NOT REGEXP '^[a-f0-9]{32}$') AS invalid_product_id,

    SUM(TRIM(product_category_name) <> ''
        AND TRIM(product_category_name) NOT REGEXP '^[a-z]+(_[a-z0-9]+)*$') AS invalid_product_category_name,

    SUM(TRIM(product_name_length) <> ''
        AND TRIM(product_name_length) NOT REGEXP '^[0-9]+$') AS invalid_name_length,

    SUM(TRIM(product_description_length) <> ''
        AND TRIM(product_description_length) NOT REGEXP '^[0-9]+$') AS invalid_description_length,

    SUM(TRIM(product_photos_qty) <> ''
        AND TRIM(product_photos_qty) NOT REGEXP '^[0-9]+$') AS invalid_photos_qty,

    SUM(TRIM(product_weight_g) <> ''
        AND TRIM(product_weight_g) NOT REGEXP '^[0-9]+$') AS invalid_weight,

    SUM(TRIM(product_length_cm) <> ''
        AND TRIM(product_length_cm) NOT REGEXP '^[0-9]+$') AS invalid_length,

    SUM(TRIM(product_height_cm) <> ''
        AND TRIM(product_height_cm) NOT REGEXP '^[0-9]+$') AS invalid_height,

    SUM(TRIM(product_width_cm) <> ''
        AND TRIM(product_width_cm) NOT REGEXP '^[0-9]+$') AS invalid_width

FROM staging_products;


-- staging_products: zero value check
SELECT
SUM(TRIM(product_weight_g) REGEXP '^[0-9]+$' 
	AND CAST(product_weight_g AS UNSIGNED) = 0) AS zero_weight,
    
SUM(TRIM(product_length_cm) REGEXP '^[0-9]+$' 
	AND CAST(product_length_cm AS UNSIGNED) = 0) AS zero_length,
    
SUM(TRIM(product_height_cm) REGEXP '^[0-9]+$' 
	AND CAST(product_height_cm AS UNSIGNED) = 0) AS zero_height,
    
SUM(TRIM(product_width_cm) REGEXP '^[0-9]+$' 
	AND CAST(product_width_cm AS UNSIGNED) = 0) AS zero_width,
    
SUM(TRIM(product_photos_qty) REGEXP '^[0-9]+$' 
	AND CAST(product_photos_qty AS UNSIGNED) = 0) AS zero_photos_qty
    
FROM staging_products;

/*
Zero-value product measurements were identified as potential business-rule violations.
Zero values are not automatically treated as invalid because the source dataset may contain legitimate zero measurements.
These records should be investigated before applying any transformation.
*/

-- staging_products: product category frequency check
SELECT
	TRIM(product_category_name) AS product_category_name, 
	COUNT(*) AS occurrences
FROM staging_products
GROUP BY TRIM(product_category_name)
ORDER BY occurrences;

-- staging_products: product weight frequency check
SELECT
	product_weight_g,
	COUNT(*) AS occurrences
FROM staging_products
GROUP BY product_weight_g
ORDER BY product_weight_g DESC;

-- staging_products: product length frequency check
SELECT
	product_length_cm,
	COUNT(*) AS occurrences
FROM staging_products
GROUP BY product_length_cm
ORDER BY product_length_cm DESC;

-- staging_products: product height frequency check
SELECT
	product_height_cm,
	COUNT(*) AS occurrences
FROM staging_products
GROUP BY product_height_cm
ORDER BY product_height_cm DESC;

-- staging_products: product width frequency check
SELECT
	product_width_cm,
	COUNT(*) AS occurrences
FROM staging_products
GROUP BY product_width_cm
ORDER BY product_width_cm DESC;

-- staging_products: duplicate product_id check
SELECT
	product_id,
	COUNT(*) AS occurrences
FROM staging_products
WHERE TRIM(product_id) REGEXP '^[a-f0-9]{32}$'
GROUP BY product_id
HAVING COUNT(*) > 1;

/* ==========================================================
3. SELLERS
========================================================== */

-- staging_sellers: empty string check
SELECT
SUM(TRIM(seller_id) = '') AS seller_id_empty,
SUM(TRIM(seller_zip_code_prefix) = '') AS zip_code_empty,
SUM(TRIM(seller_city) = '') AS city_empty,
SUM(TRIM(seller_state) = '') AS state_empty
FROM staging_sellers;


-- staging_sellers: identifier, ZIP, city and state format validation
SELECT
	SUM(TRIM(seller_id) <> ''
		AND seller_id NOT REGEXP '^[a-f0-9]{32}$'
		) AS invalid_seller_id,
        
	SUM(TRIM(seller_zip_code_prefix) <> ''
		AND seller_zip_code_prefix NOT REGEXP '^[0-9]{5}$'
		) AS invalid_seller_zip_code,
        
	SUM(TRIM(seller_city) <> ''
		AND seller_city NOT REGEXP '^[a-zA-ZÀ-ÿ]+([ -][a-zA-ZÀ-ÿ]+)*$'
		) AS suspicious_seller_city,
        
	SUM(TRIM(seller_state) <> ''
		AND seller_state NOT REGEXP '^[A-Z]{2}$'
		) AS invalid_seller_state
        
FROM staging_sellers;
/*
36 seller city values were identified by the original validation as format exceptions.
These values require review because city standardization is important for location-level analysis.
The corrected validation should be rerun before treating the count as final.
*/

-- staging_sellers: distinct city values for consistency review
SELECT
seller_city,
COUNT(*) AS occurrences
FROM staging_sellers
WHERE TRIM(seller_city) <> ''
GROUP BY seller_city
ORDER BY seller_city;
/*
Seller city names contain multiple aliases of city names.
City values should be standardized through the city_aliases.
*/

-- staging_sellers: duplicate seller_id check
SELECT
    seller_id,
    COUNT(*) AS occurrences
FROM staging_sellers
GROUP BY seller_id
HAVING COUNT(*) > 1;

/* ==========================================================
4. ORDERS
========================================================== */

-- staging_orders: empty string check
SELECT
SUM(TRIM(order_id) = '') AS order_id_empty,
SUM(TRIM(customer_id) = '') AS customer_id_empty,
SUM(TRIM(order_status) = '') AS order_status_empty,
SUM(TRIM(order_purchase_timestamp) = '') AS purchase_timestamp_empty,
SUM(TRIM(order_approved_at) = '') AS approved_timestamp_empty,
SUM(TRIM(order_delivered_carrier_date) = '') AS carrier_date_empty,
SUM(TRIM(order_delivered_customer_date) = '') AS delivered_date_empty,
SUM(TRIM(order_estimated_delivery_date) = '') AS estimated_date_empty
FROM staging_orders;

/*
160 Missing order approval, 1783 carrier date and 2965 order delivered timestamps are not automatically treated as data quality errors.
These values may be expected depending on the order lifecycle and should be validated against order status.
*/

-- staging_orders: identifier and category format validation
SELECT
	SUM(TRIM(order_id) <> ''
		AND order_id NOT REGEXP '^[a-f0-9]{32}$'
		) AS invalid_order_id,
	SUM(TRIM(customer_id) <> ''
		AND customer_id NOT REGEXP '^[a-f0-9]{32}$'
		) AS invalid_customer_id
FROM staging_orders;

-- staging_orders: invalid order status check
SELECT
	SUM(TRIM(order_status) <> ''
		AND order_status NOT IN (
			'delivered',
			'invoiced',
			'shipped',
			'processing',
			'unavailable',
			'canceled',
			'created',
			'approved')
	) AS invalid_order_status
FROM staging_orders;

-- staging_orders: order status frequency check
SELECT
order_status,
COUNT(*) AS occurrences
FROM staging_orders
GROUP BY order_status
ORDER BY occurrences DESC;

-- staging_orders: date & timestamp format validation
SELECT
	SUM(TRIM(order_purchase_timestamp) <> ''
		AND STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s') IS NULL
		) AS invalid_purchase_timestamp,
        
	SUM(TRIM(order_approved_at) <> ''
		AND STR_TO_DATE(order_approved_at, '%Y-%m-%d %H:%i:%s') IS NULL
		) AS invalid_approved_timestamp,
        
	SUM(TRIM(order_delivered_carrier_date) <> ''
		AND STR_TO_DATE(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s') IS NULL
		) AS invalid_carrier_timestamp,
        
	SUM(TRIM(order_delivered_customer_date) <> ''
		AND STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s') IS NULL
		) AS invalid_delivered_timestamp,
        
	SUM(TRIM(order_estimated_delivery_date) <> ''
		AND STR_TO_DATE(order_estimated_delivery_date, '%Y-%m-%d') IS NULL
		) AS invalid_estimated_delivery_date
FROM staging_orders;

-- staging_orders: order date range validation
SELECT
	SUM(TRIM(order_purchase_timestamp) <> ''
		AND STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s') IS NOT NULL
		AND (
			order_purchase_timestamp < '2016-01-01'
			OR STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s') >= '2019-01-01')
		) AS invalid_purchase_date,
        
	SUM(TRIM(order_approved_at) <> ''
		AND STR_TO_DATE(order_approved_at, '%Y-%m-%d %H:%i:%s') IS NOT NULL
		AND (
			STR_TO_DATE(order_approved_at, '%Y-%m-%d %H:%i:%s') < '2016-01-01'
			OR STR_TO_DATE(order_approved_at, '%Y-%m-%d %H:%i:%s') >= '2019-01-01')
	) AS invalid_approved_date,
        
	SUM(TRIM(order_delivered_carrier_date) <> ''
		AND STR_TO_DATE(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s') IS NOT NULL
		AND (
			STR_TO_DATE(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s') < '2016-01-01'
			OR STR_TO_DATE(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s') >= '2019-01-01')
		) AS invalid_carrier_date,
        
	SUM(TRIM(order_delivered_customer_date) <> ''
		AND STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s') IS NOT NULL
		AND (
			STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s') < '2016-01-01'
			OR STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s') >= '2019-01-01')
		) AS invalid_delivered_date,
        
	SUM(TRIM(order_estimated_delivery_date) <> ''
		AND STR_TO_DATE(order_estimated_delivery_date, '%Y-%m-%d') IS NOT NULL
		AND (
			STR_TO_DATE(order_estimated_delivery_date, '%Y-%m-%d') < '2016-01-01'
			OR STR_TO_DATE(order_estimated_delivery_date, '%Y-%m-%d') >= '2019-01-01')
		) AS invalid_estimated_date
FROM staging_orders;

-- staging_orders: approval timestamp consistency check
SELECT
	COUNT(*) AS order_approval_before_purchase
FROM staging_orders
WHERE TRIM(order_approved_at) <> ''
	AND STR_TO_DATE(order_approved_at, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
    AND TRIM(order_purchase_timestamp) <> ''
	AND STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
	AND STR_TO_DATE(order_approved_at, '%Y-%m-%d %H:%i:%s')
		< STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s');

-- staging_orders: carrier timestamp consistency check
SELECT
	COUNT(*) AS carrier_received_before_purchase
FROM staging_orders
WHERE TRIM(order_delivered_carrier_date) <> ''
	AND STR_TO_DATE(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
    AND TRIM(order_purchase_timestamp) <> ''
	AND STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
	AND STR_TO_DATE(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s')
		< STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s');

/*
166 orders were previously identified with carrier delivery timestamps before purchase timestamps.
This is a potential business-rule violation and should be investigated.
Rerun after the corrected date validation before treating the count as final.
*/

-- staging_orders: delivered timestamp consistency check
SELECT
	COUNT(*) AS customer_delivery_before_carrier_received
FROM staging_orders
WHERE TRIM(order_delivered_customer_date) <> ''
	AND STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
	AND TRIM(order_delivered_carrier_date) <> ''
	AND STR_TO_DATE(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
	AND STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s')
		< STR_TO_DATE(order_delivered_carrier_date, '%Y-%m-%d %H:%i:%s');

/*
23 orders were previously identified with customer delivery timestamps before carrier delivery timestamps.
This is a potential business-rule violation and should be investigated.
Rerun after the corrected date validation before treating the count as final.
*/

-- staging_orders: estimated delivery date consistency check
SELECT
	COUNT(*) AS estimated_delivery_before_purchase
FROM staging_orders
WHERE TRIM(order_estimated_delivery_date) <> ''
    AND STR_TO_DATE(order_estimated_delivery_date, '%Y-%m-%d') IS NOT NULL
    
	AND TRIM(order_purchase_timestamp) <> ''
	AND STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
	AND STR_TO_DATE(order_estimated_delivery_date, '%Y-%m-%d')
		<  DATE(STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s'));

-- staging_orders: delivered order status consistency check
SELECT
	COUNT(*) AS delivered_orders_missing_delivery_date
FROM staging_orders
WHERE order_status = 'delivered'
	AND (
		TRIM(order_delivered_customer_date) = ''
		OR STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s') IS NULL);

/*
8 delivered orders were previously identified without a customer delivery timestamp.
This conflicts with the expected lifecycle of a delivered order and should be investigated.
*/

-- staging_orders: canceled order delivery consistency check
SELECT
	COUNT(*) AS canceled_orders_with_delivery_date
FROM staging_orders
WHERE order_status = 'canceled'
	AND TRIM(order_delivered_customer_date) <> ''
	AND STR_TO_DATE(order_delivered_customer_date, '%Y-%m-%d %H:%i:%s') IS NOT NULL;

/*
6 canceled orders were previously identified with customer delivery timestamps.
These records should be investigated because the delivery timestamp conflicts with the canceled status.
*/

-- staging_orders: duplicate order_id check
SELECT
order_id,
COUNT(*) AS occurrences
FROM staging_orders
WHERE TRIM(order_id) REGEXP '^[a-f0-9]{32}$'
GROUP BY order_id
HAVING COUNT(*) > 1;

-- staging_orders: Orders without any items
SELECT
    COUNT(*) AS orders_without_items
FROM staging_orders o
LEFT JOIN staging_order_items oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL;

/* 775 orders are without order items */

/* ==========================================================
5. ORDER ITEMS
========================================================== */

-- staging_order_items: empty string check
SELECT
SUM(TRIM(order_id) = '') AS order_id_empty,
SUM(TRIM(order_item_id) = '') AS order_item_id_empty,
SUM(TRIM(product_id) = '') AS product_id_empty,
SUM(TRIM(seller_id) = '') AS seller_id_empty,
SUM(TRIM(shipping_limit_date) = '') AS shipping_limit_date_empty,
SUM(TRIM(price) = '') AS price_empty,
SUM(TRIM(freight_value) = '') AS freight_value_empty
FROM staging_order_items;

-- staging_order_items: identifier format validation
SELECT
    SUM(TRIM(order_id) <> ''
        AND TRIM(order_id) NOT REGEXP '^[a-f0-9]{32}$'
        ) AS invalid_order_id,
        
	    SUM(TRIM(order_item_id) <> ''
        AND TRIM(order_item_id) NOT REGEXP '^[0-9]+$'
        ) AS invalid_order_item_id,
        
	    SUM(TRIM(product_id) <> ''
        AND TRIM(product_id) NOT REGEXP '^[a-f0-9]{32}$'
        ) AS invalid_product_id,
        
	    SUM(TRIM(seller_id) <> ''
        AND TRIM(seller_id) NOT REGEXP '^[a-f0-9]{32}$'
        ) AS invalid_seller_id
FROM staging_order_items;

-- staging_order_items: shipping date format validation
SELECT
	SUM(TRIM(shipping_limit_date) <> ''
		AND STR_TO_DATE(shipping_limit_date, '%Y-%m-%d %H:%i:%s') IS NULL
		) AS invalid_shipping_limit_date
FROM staging_order_items;

-- staging_order_items: numeric format validation
SELECT
	SUM(TRIM(price) <> ''
		AND price NOT REGEXP '^[0-9]+(\.[0-9]{2})?$'
		) AS invalid_price,
        
	SUM(TRIM(freight_value) <> ''
		AND freight_value NOT REGEXP '^[0-9]+(\\.[0-9]{2})?$'
		) AS invalid_freight_value
FROM staging_order_items;

-- staging_order_items: zero value check
SELECT
	SUM(TRIM(price) REGEXP '^[0-9]+(\\.[0-9]{2})?$' 
		AND CAST(price AS DECIMAL(10,2)) = 0
        ) AS zero_price,
        
	SUM(TRIM(freight_value) REGEXP '^[0-9]+(\\.[0-9]{2})?$' 
		AND CAST(freight_value AS DECIMAL(10,2)) = 0
        ) AS zero_freight_value
FROM staging_order_items;

-- staging_order_items: shipping date business rule validation
SELECT
	COUNT(*) AS shipping_limit_before_purchase
FROM staging_order_items soi
JOIN staging_orders so
	ON soi.order_id = so.order_id
WHERE TRIM(soi.shipping_limit_date) <> ''
	AND STR_TO_DATE(soi.shipping_limit_date, '%Y-%m-%d %H:%i:%s') IS NOT NULL
	
    AND TRIM(so.order_purchase_timestamp) <> ''
	AND STR_TO_DATE(so.order_purchase_timestamp, '%Y-%m-%d %H:%i:%s') IS NOT NULL
	
    AND STR_TO_DATE(soi.shipping_limit_date, '%Y-%m-%d %H:%i:%s')
		< STR_TO_DATE(so.order_purchase_timestamp, '%Y-%m-%d %H:%i:%s');

-- staging_order_items: duplicate order_id and order_item_id check
SELECT
	order_id,
	order_item_id,
	COUNT(*) AS occurrences
FROM staging_order_items
WHERE order_id REGEXP '^[a-f0-9]+$'
	AND order_item_id REGEXP '^[a-f0-9]+$'
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;

-- staging_order_items: referential integrity check -> staging_orders, staging_products and staging_sellers
SELECT
	soi.order_item_id,
	soi.order_id,
	soi.product_id,
	soi.seller_id
FROM staging_order_items soi
LEFT JOIN staging_orders so
	ON soi.order_id = so.order_id
LEFT JOIN staging_products sp
	ON soi.product_id = sp.product_id
LEFT JOIN staging_sellers ss
	ON soi.seller_id = ss.seller_id
WHERE so.order_id IS NULL
	OR sp.product_id IS NULL
	OR ss.seller_id IS NULL;

/* ==========================================================
6. ORDER PAYMENTS
========================================================== */

-- staging_order_payments: empty string check
SELECT
SUM(TRIM(order_id) = '') AS order_id_empty,
SUM(TRIM(payment_sequential) = '') AS payment_sequential_empty,
SUM(TRIM(payment_type) = '') AS payment_type_empty,
SUM(TRIM(payment_installments) = '') AS payment_installments_empty,
SUM(TRIM(payment_value) = '') AS payment_value_empty
FROM staging_order_payments;

-- staging_order_payments: identifier and numeric format validation
SELECT
		SUM(TRIM(order_id) <> ''
		AND order_id NOT REGEXP '^[a-f0-9]{32}$'
		) AS invalid_order_id,

	SUM(TRIM(payment_sequential) <> ''
		AND payment_sequential NOT REGEXP '^[0-9]+$'
		) AS invalid_payment_sequential,
        
	SUM(TRIM(payment_installments) <> ''
		AND payment_installments NOT REGEXP '^[0-9]+$'
		) AS invalid_payment_installments,
        
	SUM(TRIM(payment_value) <> ''
		AND payment_value NOT REGEXP '^[0-9]+(\.[0-9]{2})?$'
		) AS invalid_payment_value
FROM staging_order_payments;

-- staging_order_payments: payment type frequency check
SELECT
	payment_type,
	COUNT(*) AS occurrences
FROM staging_order_payments
GROUP BY payment_type
ORDER BY occurrences DESC;

-- staging_order_payments: payment type validation
SELECT
	SUM(TRIM(payment_type) <> ''
		AND payment_type NOT IN ('credit_card', 'boleto', 'voucher', 'debit_card', 'not_defined')
		) AS invalid_payment_type
FROM staging_order_payments;

-- staging_order_payments: zero value check
SELECT
	SUM(TRIM(payment_sequential) REGEXP '^[0-9]+$' 
		AND CAST(payment_sequential AS UNSIGNED) = 0) AS zero_payment_sequential,
        
	SUM(TRIM(payment_installments) REGEXP '^[0-9]+$' 
		AND CAST(payment_installments AS UNSIGNED) = 0) AS zero_installments,
        
	SUM(TRIM(payment_value) REGEXP '^[0-9]+(\.[0-9]{2})?$' 
		AND CAST(payment_value AS DECIMAL(10,2)) = 0) AS zero_payment_value
FROM staging_order_payments;

/*
2 zero-installment payment records were identified.
9 zero-value payment records were identified.
These values may be associated with specific payment types such as voucher and should be investigated before being treated as invalid.
*/

-- veryfying zero installment
SELECT
    order_id,
    COUNT(*) AS total_payment_rows,
    SUM(CASE WHEN CAST(payment_installments AS UNSIGNED) = 0 THEN 1 ELSE 0 END) AS zero_installment_rows
FROM staging_order_payments
GROUP BY order_id
HAVING SUM(CASE WHEN CAST(payment_installments AS UNSIGNED) = 0 THEN 1 ELSE 0 END) = COUNT(*)
   AND COUNT(*) > 1;


-- staging_order_payments: duplicate order_id and payment_sequential check
SELECT
	order_id,
	payment_sequential,
	COUNT(*) AS occurrences
FROM staging_order_payments
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;


-- staging_order_payments: referential integrity check -> staging_orders
SELECT
	sop.order_id
FROM staging_order_payments sop
LEFT JOIN staging_orders so
	ON sop.order_id = so.order_id
WHERE so.order_id IS NULL;

/* ==========================================================
7. GEOLOCATION
========================================================== */

-- staging_geolocation: empty string check
SELECT
SUM(TRIM(geolocation_zip_code_prefix) = '') AS zip_code_empty,
SUM(TRIM(geolocation_lat) = '') AS latitude_empty,
SUM(TRIM(geolocation_lng) = '') AS longitude_empty,
SUM(TRIM(geolocation_city) = '') AS city_empty,
SUM(TRIM(geolocation_state) = '') AS state_empty
FROM staging_geolocation;

-- staging_geolocation: column format validation
SELECT
	SUM(TRIM(geolocation_zip_code_prefix) <> ''
		AND geolocation_zip_code_prefix NOT REGEXP '^[0-9]{5}$'
		) AS invalid_zip_code,
	SUM(TRIM(geolocation_city) <> ''
		AND geolocation_city NOT REGEXP '^[a-zA-ZÀ-ÿ]+([ -][a-zA-ZÀ-ÿ]+)*$'
		) AS invalid_city_format,
	SUM(TRIM(geolocation_state) <> ''
		AND geolocation_state NOT REGEXP '^[A-Z]{2}$'
		) AS invalid_state_format
FROM staging_geolocation;

/*
46 geolocation city values were previously identified as format exceptions.
These values require review if city-level analytics will be performed.
*/

-- staging_geolocation: coordinate format validation
SELECT
	SUM(TRIM(geolocation_lat) <> ''
		AND geolocation_lat NOT REGEXP '^-?[0-9]+(\.[0-9]+)?$'
		) AS invalid_latitude_format,
	SUM(TRIM(geolocation_lng) <> ''
		AND geolocation_lng NOT REGEXP '^-?[0-9]+(\.[0-9]+)?$'
		) AS invalid_longitude_format
FROM staging_geolocation;

-- staging_geolocation: latitude and longitude range validation
SELECT
	SUM(geolocation_lat REGEXP '^-?[0-9]+(\.[0-9]+)?$'
	AND CAST(geolocation_lat AS DECIMAL(10,6)) NOT BETWEEN -90 AND 90
	) AS invalid_latitudes,
SUM(geolocation_lng REGEXP '^-?[0-9]+(\.[0-9]+)?$'
	AND CAST(geolocation_lng AS DECIMAL(10,6)) NOT BETWEEN -180 AND 180
	) AS invalid_longitudes
FROM staging_geolocation;

-- staging_geolocation: Brazil coordinate range validation
SELECT
SUM(
geolocation_lat REGEXP '^-?[0-9]+(\.[0-9]+)?$'
AND CAST(geolocation_lat AS DECIMAL(10,6)) NOT BETWEEN -34 AND 5
) AS outside_brazil_latitude,
SUM(
geolocation_lng REGEXP '^-?[0-9]+(\.[0-9]+)?$'
AND CAST(geolocation_lng AS DECIMAL(10,6)) NOT BETWEEN -74 AND -34
) AS outside_brazil_longitude
FROM staging_geolocation;

-- staging_geolocation: duplicate location check
SELECT
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state,
    COUNT(*) AS occurrences
FROM staging_geolocation
GROUP BY
    geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state
HAVING COUNT(*) > 1
LIMIT 10;


/* ==========================================================
8. ORDER REVIEWS
========================================================== */

-- staging_order_reviews: empty string check
SELECT
	SUM(TRIM(review_id) = '') AS review_id_empty,
	SUM(TRIM(order_id) = '') AS order_id_empty,
	SUM(TRIM(review_score) = '') AS review_score_empty,
	SUM(TRIM(review_comment_title) = '') AS review_title_empty,
	SUM(TRIM(review_comment_message) = '') AS review_message_empty,
	SUM(TRIM(review_creation_date) = '') AS review_creation_date_empty,
	SUM(TRIM(review_answer_timestamp) = '') AS review_answer_timestamp_empty
FROM staging_order_reviews;

/*
87,657 review titles and 58,256 review messages were previously identified as empty.
Empty review text is considered potentially valid because written comments are optional.
*/

-- staging_order_reviews: leading and trailing space check
SELECT
	SUM(review_comment_title <> '' AND review_comment_title <> TRIM(review_comment_title)
		) AS review_title_spaces,
        
	SUM(review_comment_message <> '' AND review_comment_message <> TRIM(review_comment_message)
		) AS review_message_spaces
FROM staging_order_reviews;

/*
1,998 review titles and 8,120 review messages were previously identified with leading or trailing spaces.
These can be safely handled during text standardization without changing the review content.
*/

-- staging_order_reviews: format and range validation
SELECT
	SUM(TRIM(review_id) <> ''
		AND review_id NOT REGEXP '^[a-f0-9]+$'
		) AS invalid_review_id,
		
	SUM(TRIM(order_id) <> ''
		AND order_id NOT REGEXP '^[a-f0-9]+$'
		) AS invalid_order_id,
		
	SUM(TRIM(review_score) <> ''
		AND review_score NOT REGEXP '^[1-5]$'
		) AS invalid_review_scores,
		
	 SUM(review_creation_date <> ''
		AND STR_TO_DATE(review_creation_date, '%Y-%m-%d %H:%i:%s') IS NULL
		) AS invalid_review_creation_date,
		
	 SUM(review_answer_timestamp <> ''
		AND STR_TO_DATE(review_answer_timestamp, '%Y-%m-%d %H:%i:%s') IS NULL
		) AS invalid_review_answer_timestamp
FROM staging_order_reviews;

/* review_creation_date & review_answer_timestamp has non parsable dates */

-- staging_order_reviews: review creation timestamp consistency check
SELECT
	COUNT(*) AS reviews_before_order
FROM staging_order_reviews sor
JOIN staging_orders so
	ON sor.order_id = so.order_id
WHERE TRIM(sor.review_creation_date) <> ''
	AND STR_TO_DATE(sor.review_creation_date, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
    AND TRIM(so.order_purchase_timestamp) <> ''
	AND STR_TO_DATE(so.order_purchase_timestamp, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
	AND STR_TO_DATE(sor.review_creation_date, '%Y-%m-%d %H:%i:%s')
		< STR_TO_DATE(so.order_purchase_timestamp, '%Y-%m-%d %H:%i:%s');

/*
Reviews should not normally be created before the related order was purchased.
Any records returned by this check should be investigated as potential timestamp inconsistencies.
*/

-- staging_order_reviews: review answer timestamp consistency check
SELECT
	COUNT(*) AS answers_before_review
FROM staging_order_reviews
WHERE TRIM(review_answer_timestamp) <> ''
	AND STR_TO_DATE(review_answer_timestamp, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
	AND TRIM(review_creation_date) <> ''
	AND STR_TO_DATE(review_creation_date, '%Y-%m-%d %H:%i:%s') IS NOT NULL
    
	AND STR_TO_DATE(review_answer_timestamp, '%Y-%m-%d %H:%i:%s')
		< STR_TO_DATE(review_creation_date, '%Y-%m-%d %H:%i:%s');

/*
A review answer timestamp should not occur before the review creation timestamp.
Any records returned should be investigated as potential timestamp inconsistencies.
*/

-- staging_order_reviews: duplicate review id check
SELECT review_id, COUNT(*) AS occurrences
FROM staging_order_reviews
GROUP BY review_id
HAVING COUNT(*) > 1;

-- staging_order_reviews: duplicate review check
SELECT
review_id,
order_id,
COUNT(*) AS occurrences
FROM staging_order_reviews
GROUP BY review_id, order_id
HAVING COUNT(*) > 1;

-- staging_order_reviews: referential integrity check -> staging_orders
SELECT
	sor.order_id
FROM staging_order_reviews sor
LEFT JOIN staging_orders so
	ON sor.order_id = so.order_id
WHERE so.order_id IS NULL;

/* ==========================================================
9. PRODUCT CATEGORY TRANSLATION
========================================================== */

-- staging_product_category_name_translation: empty string check
SELECT
	SUM(TRIM(product_category_name) = '') AS portuguese_category_empty,
	SUM(TRIM(product_category_name_english) = '') AS english_category_empty
FROM staging_product_category_name_translation;

-- staging_product_category_name_translation: leading and trailing space check
SELECT
	SUM(product_category_name <> '' 
		AND product_category_name <> TRIM(product_category_name)
		) AS portuguese_category_spaces,
        
	SUM(product_category_name_english <> '' 
		AND product_category_name_english <> TRIM(product_category_name_english)
		) AS english_category_spaces
FROM staging_product_category_name_translation;

-- staging_product_category_name_translation: duplicate Portuguese category check
SELECT
product_category_name,
COUNT(*) AS occurrences
FROM staging_product_category_name_translation
GROUP BY product_category_name
HAVING COUNT(*) > 1;

-- staging_product_category_name_translation: duplicate English category check
SELECT
product_category_name_english,
COUNT(*) AS occurrences
FROM staging_product_category_name_translation
GROUP BY product_category_name_english
HAVING COUNT(*) > 1;

-- staging_product_category_name_translation: missing translation check
SELECT
	sp.product_category_name
FROM staging_products sp
LEFT JOIN staging_product_category_name_translation snt
ON sp.product_category_name = snt.product_category_name
WHERE TRIM(sp.product_category_name) <> ''
	AND snt.product_category_name IS NULL
GROUP BY sp.product_category_name;

/*
Some product category values in staging_products are not present in the translation table.
These categories will require either a translation mapping or an explicit handling rule before English category reporting.
*/

/* ==========================================================
VALIDATION FINDINGS SUMMARY
========================================================== */
/*
Data quality findings:

- staging_products: Product category, name length, description length and photo quantity contain 610 missing rows.
- staging_products: 2 product dimension records contain missing dimension values.

- staging_order_reviews: 87,657 review titles and 58,256 review messages fields contain a large number of empty values; these are considered potentially valid because review text is optional.
- staging_order_reviews: 1998 Review title and 8120 Review title message fields contain leading/trailing spaces that should be removed during standardization.
- staging_order_reviews: 1 Review creation date & 1 Review answer timestamp has non parsable dates.

- staging_product_category_name_translation: 2 Product category name is missing compared to valid product category name in product table.

- City values across staging tables contain multiple representations of the same city and should be resolved through the city alias and master city mapping process.

*/

/* ==========================================================
BUSINESS RULE FINDINGS SUMMARY
========================================================== */
/*
Business rule findings:

- staging_products: 4 records contain zero product weight or dimension values and should be investigated as potential business-rule exceptions.

- staging_orders: 160 records have missing order approval timestamps, 1,783 have missing carrier timestamps, and 2,965 have missing customer delivery timestamps. 
					These missing values are treated as potentially valid based on order lifecycle conditions.
- staging_orders: 166 orders have carrier timestamps earlier than purchase timestamps, violating the expected order timeline.
- staging_orders: 23 orders have customer delivery timestamps earlier than carrier timestamps, violating the expected order timeline.
- staging_orders: 8 delivered orders do not have customer delivery timestamps, violating the expected delivery-status consistency rule.
- staging_orders: 6 canceled orders have customer delivery timestamps, violating the expected cancellation-status consistency rule.
- staging_orders: 775 orders are without order items.

- staging_order_payments: 2 payment records contain zero installments and should be investigated as potential business-rule exceptions.
- staging_order_payments: 9 payment records contain zero payment values and should be investigated as potential business-rule exceptions.

- staging_order_reviews: 74 review creation timestamps occur before the related order purchase timestamp, violating the expected temporal sequence.
- staging_order_reviews: 8320 reviews before customer delivery date, potentially late deliveries.   
*/

-- ==========================================================
-- VALIDATION APPROACH
-- ==========================================================
/*
Staging data is intentionally retained as VARCHAR during ingestion.
Validation therefore follows a three-stage approach:

1. Identify real NULL values, empty strings.
2. Validate the textual format before converting VARCHAR values into numeric or date types.
3. Apply business rules only to the values that have passed format validation.

Records identified as data quality exceptions are not automatically deleted.
Each exception will be handled during transformation according to its business meaning and analytical impact.

City values will be standardized using normalized city names and city aliases before joining to the master cities table.

*/
