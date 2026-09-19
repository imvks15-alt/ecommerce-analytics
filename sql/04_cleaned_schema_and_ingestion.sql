-- =========================================================
-- OLIST E-COMMERCE DATABASE
-- CREATION & INGESTION OF TRANSFORMED SCHEMA & DATA
-- =========================================================
/*
Purpose: Transform staging (VARCHAR) data into typed, keyed,
            business rule aware relational tables.
   
   Stages in this file:
     - Cleaned schema DDL (typed tables with PKs, FKs, UNIQUE keys)
     - Cleaned data ingestion from staging
     - Post-ingestion row count reconciliation
   
   Business rules applied during ingestion:
   - approval_at < purchase → NULL
   - carrier_date < purchase → NULL
   - customer_delivery < carrier_date → NULL
   - canceled/unavailable orders → delivery date NULL
   - City names standardized via city_aliases
   - Category translation with backfill for 2 missing categories
   
   NOTE:
   - FK constraints enforced after load (SET FOREIGN_KEY_CHECKS = 0/1)
     to allow clean rebuilds without dependency ordering issues
*/


USE olist_ecommerce; 			-- selecting database

SET FOREIGN_KEY_CHECKS = 0;		-- disabling all foreign key checks

-- =========================================================
-- CUSTOMERS
-- ==========================================================
DROP TABLE IF EXISTS olist_customers;
CREATE TABLE olist_customers (
	customer_id 				CHAR(32) PRIMARY KEY,
	customer_unique_id 			CHAR(32) NOT NULL,
    customer_zip_code_prefix 	CHAR(5),
    customer_city 				VARCHAR(100),
    customer_state 				CHAR(2)
);

-- =========================================================
-- PRODUCTS
-- ==========================================================
DROP TABLE IF EXISTS olist_products;
CREATE TABLE olist_products (
    product_id 					CHAR(32) PRIMARY KEY,
    product_category_name 		VARCHAR(100),
    product_name_length 		INT,
    product_description_length 	INT,
    product_photos_qty 			INT,
    product_weight_g 			INT,
    product_length_cm 			INT,
    product_height_cm 			INT,
    product_width_cm 			INT
);

-- =========================================================
-- SELLERS
-- ==========================================================
DROP TABLE IF EXISTS olist_sellers;
CREATE TABLE olist_sellers (
    seller_id 				CHAR(32) PRIMARY KEY,
    seller_zip_code_prefix 	CHAR(5),
    seller_city 			VARCHAR(100),
    seller_state 			CHAR(2)
);

-- =========================================================
-- ORDERS
-- ==========================================================
DROP TABLE IF EXISTS olist_orders;
CREATE TABLE olist_orders (
    order_id 						CHAR(32) PRIMARY KEY,
    customer_id 					CHAR(32) NOT NULL,
    order_status 					VARCHAR(50),
    order_purchase_timestamp 		DATETIME NOT NULL,
    order_approved_at 				DATETIME,
    order_delivered_carrier_date 	DATETIME,
    order_delivered_customer_date 	DATETIME,
    order_estimated_delivery_date 	DATETIME,
    
    FOREIGN KEY (customer_id) 
    REFERENCES olist_customers(customer_id)
);

-- =========================================================
-- ORDER ITEMS
-- ==========================================================
DROP TABLE IF EXISTS olist_order_items;
CREATE TABLE olist_order_items (
    order_id 			CHAR(32),
    order_item_id 		INT NOT NULL,
    product_id 			CHAR(32) NOT NULL,
    seller_id 			CHAR(32) NOT NULL,
    shipping_limit_date DATETIME,
    price 				DECIMAL(10,2),
    freight_value 		DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id),

    FOREIGN KEY (order_id) 
    REFERENCES olist_orders(order_id),
    
    FOREIGN KEY (product_id)
    REFERENCES olist_products(product_id),
	
    FOREIGN KEY (seller_id)
    REFERENCES olist_sellers(seller_id)
);

-- =========================================================
-- ORDER PAYMENTS
-- ==========================================================
DROP TABLE IF EXISTS olist_order_payments;
CREATE TABLE olist_order_payments (
    order_id 				CHAR(32),
    payment_sequential 		INT,
    payment_type 			VARCHAR(50),
    payment_installments 	INT,
    payment_value 			DECIMAL(10,2),
    PRIMARY KEY (order_id, payment_sequential),
    
    FOREIGN KEY (order_id) 
    REFERENCES olist_orders(order_id)
);

-- =========================================================
-- ORDER REVIEWS
-- ==========================================================
DROP TABLE IF EXISTS olist_order_reviews;
CREATE TABLE olist_order_reviews (
    review_id 				CHAR(32),
    order_id 				CHAR(32),
    review_score 			INT,
    review_comment_title 	VARCHAR(255),
    review_comment_message 	TEXT,
    review_creation_date 	DATETIME,
    review_answer_timestamp DATETIME,
    
    UNIQUE KEY uq_review_order (review_id, order_id),
    
    FOREIGN KEY (order_id) 
    REFERENCES olist_orders(order_id)
);


-- =========================================================
-- GEOLOCATION
-- ==========================================================
DROP TABLE IF EXISTS olist_geolocation;
CREATE TABLE olist_geolocation (
    geolocation_zip_code_prefix CHAR(5),
    geolocation_lat 			DECIMAL(10,6),
    geolocation_lng 			DECIMAL(10,6),
    geolocation_city 			VARCHAR(100),
    geolocation_state 			CHAR(2),
    
    UNIQUE KEY uq_geolocation (
		geolocation_zip_code_prefix, geolocation_lat, geolocation_lng, 
        geolocation_city, geolocation_state)
);


-- =========================================================
-- PRODUCT CATEGORY NAME TRANSLATION
-- ==========================================================
DROP TABLE IF EXISTS olist_product_category_name_translation;
CREATE TABLE olist_product_category_name_translation (
    product_category_name 			VARCHAR(100) UNIQUE NOT NULL,
    product_category_name_english 	VARCHAR(100) NOT NULL
);

-- =========================================================
-- INGESTION:- DATA TRANSFORMATION
-- =========================================================

-- =========================================================
-- CUSTOMER
-- ==========================================================
INSERT INTO olist_customers (
	customer_id, 
    customer_unique_id, 
    customer_zip_code_prefix, 
    customer_city, 
    customer_state
)
SELECT
	oc.customer_id, 
    oc.customer_unique_id, 
    oc.customer_zip_code_prefix, 
    ca.normalized_city, 
    oc.customer_state
FROM staging_customers oc
JOIN city_aliases ca
    ON oc.customer_city = ca.original_city
		AND oc.customer_state = ca.state_code;


-- =========================================================
-- PRODUCTS
-- ==========================================================
INSERT INTO olist_products (
    product_id,
    product_category_name,
    product_name_length,
    product_description_length,
    product_photos_qty,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
)
SELECT
    TRIM(product_id),
	CASE
        WHEN TRIM(product_category_name) <> ''
            THEN TRIM(product_category_name)
        ELSE NULL
    END,
    CASE
        WHEN TRIM(product_name_length) <> ''
            THEN CAST(TRIM(product_name_length) AS UNSIGNED)
        ELSE NULL
    END,
    CASE
        WHEN TRIM(product_description_length) <> ''
            THEN CAST(TRIM(product_description_length) AS UNSIGNED)
        ELSE NULL
    END,
    CASE
        WHEN TRIM(product_photos_qty) <> ''
            THEN CAST(TRIM(product_photos_qty) AS UNSIGNED)
        ELSE NULL
    END,
    CASE
        WHEN TRIM(product_weight_g) <> ''
            THEN CAST(TRIM(product_weight_g) AS UNSIGNED)
        ELSE NULL
    END,

    CASE
        WHEN TRIM(product_length_cm) <> ''
            THEN CAST(TRIM(product_length_cm) AS UNSIGNED)
        ELSE NULL
    END,
    CASE
        WHEN TRIM(product_height_cm) <> ''
            THEN CAST(TRIM(product_height_cm) AS UNSIGNED)
        ELSE NULL
    END,
    CASE
        WHEN TRIM(product_width_cm) <> ''
            THEN CAST(TRIM(product_width_cm) AS UNSIGNED)
        ELSE NULL
    END
FROM staging_products;


-- =========================================================
-- SELLERS
-- ==========================================================
INSERT INTO olist_sellers (
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
)
SELECT
    ss.seller_id,
    ss.seller_zip_code_prefix,
    ca.normalized_city,
    ss.seller_state
FROM staging_sellers ss
LEFT JOIN city_aliases ca
    ON ss.seller_city = ca.original_city
		AND ss.seller_state = ca.state_code;


-- =========================================================
-- ORDERS
-- ==========================================================
INSERT INTO olist_orders (
    order_id,
    customer_id,
	order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
)
SELECT
    order_id,
    customer_id,
     IF(order_status IN (
			'delivered',
			'invoiced',
			'shipped',
			'processing',
			'unavailable',
			'canceled',
			'created',
			'approved'), order_status,'unknown'),

    STR_TO_DATE(order_purchase_timestamp,'%Y-%m-%d %H:%i:%s'),

    CASE
        WHEN TRIM(order_approved_at) = ''
        THEN NULL

        WHEN TRIM(order_approved_at) <> ''
             AND TRIM(order_purchase_timestamp) <> ''
             AND STR_TO_DATE(order_approved_at,'%Y-%m-%d %H:%i:%s')
				< STR_TO_DATE(order_purchase_timestamp,'%Y-%m-%d %H:%i:%s')
        THEN NULL
        
        ELSE STR_TO_DATE(order_approved_at,'%Y-%m-%d %H:%i:%s')
    END,

    CASE
        WHEN TRIM(order_delivered_carrier_date) = ''
        THEN NULL

        WHEN TRIM(order_delivered_carrier_date) <> ''
             AND TRIM(order_purchase_timestamp) <> ''
             AND STR_TO_DATE(order_delivered_carrier_date,'%Y-%m-%d %H:%i:%s')
				< STR_TO_DATE(order_purchase_timestamp,'%Y-%m-%d %H:%i:%s')
        THEN NULL

        ELSE STR_TO_DATE( order_delivered_carrier_date,'%Y-%m-%d %H:%i:%s')
    END,

    CASE
        WHEN TRIM(order_delivered_customer_date) = ''
        THEN NULL

        WHEN order_status IN ('canceled', 'unavailable')
        THEN NULL

        WHEN TRIM(order_delivered_customer_date) <> ''
             AND TRIM(order_delivered_carrier_date) <> ''
             AND STR_TO_DATE( order_delivered_customer_date,'%Y-%m-%d %H:%i:%s')
				< STR_TO_DATE(order_delivered_carrier_date,'%Y-%m-%d %H:%i:%s')
        THEN NULL

        ELSE STR_TO_DATE(order_delivered_customer_date,'%Y-%m-%d %H:%i:%s')
    END,

    CASE
        WHEN TRIM(order_estimated_delivery_date) <> ''
        THEN STR_TO_DATE(order_estimated_delivery_date,'%Y-%m-%d %H:%i:%s')
        ELSE NULL
    END

FROM staging_orders;


-- =========================================================
-- ORDERS ITEMS
-- ==========================================================
INSERT INTO olist_order_items (
	order_id, 
    order_item_id, 
    product_id, 
    seller_id, 
    shipping_limit_date, 
    price, 
    freight_value
)
SELECT
	order_id, 
    order_item_id ,
    product_id, 
    seller_id,
    CASE
		WHEN TRIM(shipping_limit_date) <> ''
		THEN STR_TO_DATE(shipping_limit_date, '%Y-%m-%d %H:%i:%s')
		ELSE NULL
	END,
    
    IF(TRIM(price) <> '', CAST(price AS DECIMAL(10,2)), NULL), 
    
    IF(TRIM(freight_value) <> '', CAST(freight_value AS DECIMAL(10,2)), NULL)
    
FROM staging_order_items;


-- =========================================================
-- ORDER PAYMENTS
-- ==========================================================
TRUNCATE TABLE olist_order_payments;
INSERT INTO olist_order_payments (
	order_id, 
    payment_sequential, 
    payment_type, 
    payment_installments, 
    payment_value
)
SELECT
	order_id, 
    CAST(payment_sequential AS UNSIGNED), 
    IF(payment_type IN ('credit_card', 'boleto', 'voucher', 'debit_card', 'not_defined'), payment_type, 'not_defined'),
    CAST(payment_installments AS UNSIGNED), 
    CAST(payment_value AS DECIMAL(10,2))
FROM staging_order_payments;


-- =========================================================
-- GEOLOCATION
-- ==========================================================
INSERT INTO olist_geolocation (
   geolocation_zip_code_prefix,
    geolocation_lat,
    geolocation_lng,
    geolocation_city,
    geolocation_state
)
SELECT
    DISTINCT sg.geolocation_zip_code_prefix,
    
   CAST(sg.geolocation_lat AS DECIMAL(10,6)),
   
   CAST(sg.geolocation_lng AS DECIMAL(10,6)),
   
   ca.normalized_city,
   sg.geolocation_state
   
FROM staging_geolocation sg
LEFT JOIN city_aliases ca
    ON sg.geolocation_city = ca.original_city
		AND sg.geolocation_state = ca.state_code;
        
        
-- =========================================================
-- ORDER REVIEWS
-- ==========================================================
INSERT INTO olist_order_reviews (
    review_id,
    order_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_creation_date,
    review_answer_timestamp
)
SELECT
    review_id,
    order_id,
    
    IF(TRIM(review_score) <> '', CAST(TRIM(review_score) AS UNSIGNED), NULL),
    
    IF(TRIM(review_comment_title) <> '', TRIM(review_comment_title), NULL),
    
    IF(UPPER(TRIM(review_comment_message)) IN ('', 'N/A'), NULL, TRIM(review_comment_message)),
    
    CASE
        WHEN TRIM(review_creation_date) = '' THEN NULL
        WHEN TRIM(review_creation_date) NOT REGEXP
             '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN NULL
        ELSE STR_TO_DATE(TRIM(review_creation_date), '%Y-%m-%d %H:%i:%s')
    END,
    
    CASE
		WHEN TRIM(review_answer_timestamp) = '' THEN NULL
		WHEN TRIM(review_answer_timestamp) NOT REGEXP
             '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$' THEN NULL
		ELSE STR_TO_DATE(TRIM(review_answer_timestamp), '%Y-%m-%d %H:%i:%s')
    END
    
FROM staging_order_reviews;


-- =========================================================
-- PRODUCT CATEGORY NAME TRANSLATION
-- ==========================================================
INSERT INTO olist_product_category_name_translation (
	product_category_name,
    product_category_name_english
)
SELECT
	product_category_name,
    product_category_name_english
FROM staging_product_category_name_translation
UNION ALL
SELECT
	sp.product_category_name,
    CASE TRIM(sp.product_category_name)
        WHEN 'portateis_cozinha_e_preparadores_de_alimentos' 
        THEN 'portable_kitchen_and_food_preparation_appliances'
        WHEN 'pc_gamer' THEN 'pc_gamer'
        ELSE NULL
    END AS product_category_name_english
FROM staging_product_category_name_translation snt
RIGHT JOIN staging_products sp
	ON snt.product_category_name = sp.product_category_name
WHERE snt.product_category_name IS NULL
	AND TRIM(sp.product_category_name) <> ''
GROUP BY sp.product_category_name;


SET FOREIGN_KEY_CHECKS = 1;		-- enabling foreign key check


-- =======================================================================
-- POST-INGESTION ROW COUNT CHECK
-- =======================================================================
SELECT 'olist_customers' AS table_name, COUNT(*) AS total_rows
FROM olist_customers
UNION ALL
SELECT 'olist_products', COUNT(*)
FROM olist_products
UNION ALL
SELECT 'olist_sellers', COUNT(*)
FROM olist_sellers
UNION ALL
SELECT 'olist_orders', COUNT(*)
FROM olist_orders
UNION ALL
SELECT 'olist_order_items', COUNT(*)
FROM olist_order_items
UNION ALL
SELECT 'olist_order_payments', COUNT(*)
FROM olist_order_payments
UNION ALL
SELECT 'olist_geolocation', COUNT(*)
FROM olist_geolocation
UNION ALL
SELECT 'olist_order_reviews', COUNT(*)
FROM olist_order_reviews
UNION ALL
SELECT 'olist_product_category_name_translation', COUNT(*)
FROM olist_product_category_name_translation;