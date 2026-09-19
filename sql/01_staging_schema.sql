-- ===============================================================
-- OLIST E-COMMERCE DATABASE
-- STAGING TABLES
-- ===============================================================
/*
 STAGING LAYER PURPOSE:
The staging layer stores raw CSV data with no transformation.
VARCHAR is intentionally used for most columns so that raw values,
including malformed, missing, or unexpected values, can be loaded
without any type conversion.

Data quality validation are performed after ingestion into staging 
tables and Type conversion when loading into the cleaned Olist tables.
*/

CREATE DATABASE IF NOT EXISTS olist_ecommerce;

USE olist_ecommerce;

-- ===============================================================
-- 1. CUSTOMERS
-- ===============================================================
CREATE TABLE IF NOT EXISTS staging_customers (
	customer_id 				VARCHAR(50),
	customer_unique_id 			VARCHAR(50),
	customer_zip_code_prefix 	VARCHAR(20),
	customer_city 				VARCHAR(100),
	customer_state 				VARCHAR(100)
);

-- ===============================================================
-- 2. PRODUCTS
-- ===============================================================
CREATE TABLE IF NOT EXISTS staging_products (
	product_id 					VARCHAR(50),
    product_category_name     	VARCHAR(100),
    product_name_length       	VARCHAR(20),
    product_description_length 	VARCHAR(20),
    product_photos_qty 			VARCHAR(20),
    product_weight_g 			VARCHAR(20),
    product_length_cm			VARCHAR(20),
    product_height_cm 			VARCHAR(20),
    product_width_cm 			VARCHAR(20)
);

-- ===============================================================
-- 3. SELLERS
-- ===============================================================
CREATE TABLE IF NOT EXISTS staging_sellers (
	seller_id 				VARCHAR(50),
	seller_zip_code_prefix 	VARCHAR(20),
	seller_city 			VARCHAR(100),
    seller_state 			VARCHAR(100)
);

-- ===============================================================
-- 4. ORDERS
-- ===============================================================
CREATE TABLE IF NOT EXISTS staging_orders (
    order_id 						VARCHAR(50),
    customer_id 					VARCHAR(50),
    order_status 					VARCHAR(50),
    order_purchase_timestamp 		VARCHAR(50),
    order_approved_at 				VARCHAR(50),
    order_delivered_carrier_date 	VARCHAR(50),
    order_delivered_customer_date	VARCHAR(50),
    order_estimated_delivery_date 	VARCHAR(50)
);

-- ===============================================================
-- 5. ORDER ITEMS
-- ===============================================================
CREATE TABLE IF NOT EXISTS staging_order_items (
    order_id 			VARCHAR(50),
    order_item_id 		VARCHAR(50),
    product_id 			VARCHAR(50),
    seller_id 			VARCHAR(50),
    shipping_limit_date	VARCHAR(50),
    price 				VARCHAR(20),
    freight_value 		VARCHAR(20)
);

-- ===============================================================
-- 6. ORDER PAYMENTS
-- ===============================================================
CREATE TABLE IF NOT EXISTS staging_order_payments (
    order_id 				VARCHAR(50),
    payment_sequential 		VARCHAR(20),
    payment_type 			VARCHAR(50),
    payment_installments 	VARCHAR(20),
    payment_value 			VARCHAR(20)
);

-- ===============================================================
-- 7. GEOLOCATION
-- ===============================================================
CREATE TABLE IF NOT EXISTS staging_geolocation (
    geolocation_zip_code_prefix VARCHAR(20),
    geolocation_lat 			VARCHAR(30),
    geolocation_lng				VARCHAR(30),
    geolocation_city 			VARCHAR(100),
    geolocation_state 			VARCHAR(20)
);

-- ===============================================================
-- 8. ORDER REVIEWS
-- ===============================================================
CREATE TABLE IF NOT EXISTS staging_order_reviews (
    review_id 				VARCHAR(50),
    order_id 				VARCHAR(50),
    review_score 			VARCHAR(20),
    review_comment_title 	VARCHAR(255),
    review_comment_message 	TEXT,
    review_creation_date 	VARCHAR(50),
    review_answer_timestamp VARCHAR(50)
);

-- ===============================================================
-- 9. PRODUCT CATEGORY TRANSLATION
-- ===============================================================
CREATE TABLE IF NOT EXISTS staging_product_category_name_translation (
	product_category_name 			VARCHAR(100),
    product_category_name_english 	VARCHAR(100)
);
