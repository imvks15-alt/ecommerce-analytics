-- =======================================================================
-- OLIST E-COMMERCE DATABASE
-- RAW CSV INGESTION INTO STAGING TABLES
-- =======================================================================
/*
Purpose:
Load the raw Olist Brazilian E-Commerce CSV files into
the corresponding staging tables.

Notes:
1. Staging tables are truncated before each load so that
   previous data does not remain from an earlier ingestion.
2. Raw values are loaded with minimal transformation.
3. Data type conversion and business-rule handling are
   performed after ingestion during the transformation stage.
*/

-- =======================================================================
-- 1. CUSTOMERS
-- Source: olist_customers_dataset.csv
-- Target: olist_ecommerce.staging_customers
-- =======================================================================
TRUNCATE TABLE olist_ecommerce.staging_customers;

LOAD DATA LOCAL INFILE "file path"
INTO TABLE olist_ecommerce.staging_customers
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


-- =======================================================================
-- 2. PRODUCTS
-- Source: olist_products_dataset.csv
-- Target: olist_ecommerce.staging_products
-- =======================================================================
TRUNCATE TABLE olist_ecommerce.staging_products;

LOAD DATA LOCAL INFILE "file path"
INTO TABLE olist_ecommerce.staging_products
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


-- =======================================================================
-- 3. SELLERS
-- Source: olist_sellers_dataset.csv
-- Target: olist_ecommerce.staging_sellers
-- =======================================================================
TRUNCATE TABLE olist_ecommerce.staging_sellers;

LOAD DATA LOCAL INFILE "file path"
INTO TABLE olist_ecommerce.staging_sellers
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


-- =======================================================================
-- 4. ORDERS
-- Source: olist_orders_dataset.csv
-- Target: olist_ecommerce.staging_orders
-- =======================================================================
TRUNCATE TABLE olist_ecommerce.staging_orders;

LOAD DATA LOCAL INFILE "file path"
INTO TABLE olist_ecommerce.staging_orders
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


-- =======================================================================
-- 5. ORDER ITEMS
-- Source: olist_order_items_dataset.csv
-- Target: olist_ecommerce.staging_order_items
-- =======================================================================
TRUNCATE TABLE olist_ecommerce.staging_order_items;

LOAD DATA LOCAL INFILE "file path"
INTO TABLE olist_ecommerce.staging_order_items
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


-- =======================================================================
-- 6. ORDER PAYMENTS
-- Source: olist_order_payments_dataset.csv
-- Target: olist_ecommerce.staging_order_payments
-- =======================================================================
TRUNCATE TABLE olist_ecommerce.staging_order_payments;

LOAD DATA LOCAL INFILE "file path"
INTO TABLE olist_ecommerce.staging_order_payments
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


-- =======================================================================
-- 7. GEOLOCATION
-- Source: olist_geolocation_dataset.csv
-- Target: olist_ecommerce.staging_geolocation
-- =======================================================================
TRUNCATE TABLE olist_ecommerce.staging_geolocation;

LOAD DATA LOCAL INFILE "file path"
INTO TABLE olist_ecommerce.staging_geolocation
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


-- =======================================================================
-- 8. ORDER REVIEWS
-- Source: olist_order_reviews_dataset.csv
-- Target: olist_ecommerce.staging_order_reviews
-- =======================================================================
TRUNCATE TABLE olist_ecommerce.staging_order_reviews;

LOAD DATA LOCAL INFILE "file path"
INTO TABLE olist_ecommerce.staging_order_reviews
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


-- =======================================================================
-- 9. PRODUCT CATEGORY TRANSLATION
-- Source: product_category_name_translation.csv
-- Target: olist_ecommerce.staging_product_category_name_translation
-- =======================================================================
TRUNCATE TABLE olist_ecommerce.staging_product_category_name_translation;

LOAD DATA LOCAL INFILE "file path"
INTO TABLE olist_ecommerce.staging_product_category_name_translation
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;


-- =======================================================================
-- POST-INGESTION ROW COUNT CHECK
-- =======================================================================
SELECT 'staging_customers' AS table_name, COUNT(*) AS total_rows
FROM olist_ecommerce.staging_customers
UNION ALL
SELECT 'staging_products', COUNT(*)
FROM olist_ecommerce.staging_products
UNION ALL
SELECT 'staging_sellers', COUNT(*)
FROM olist_ecommerce.staging_sellers
UNION ALL
SELECT 'staging_orders', COUNT(*)
FROM olist_ecommerce.staging_orders
UNION ALL
SELECT 'staging_order_items', COUNT(*)
FROM olist_ecommerce.staging_order_items
UNION ALL
SELECT 'staging_order_payments', COUNT(*)
FROM olist_ecommerce.staging_order_payments
UNION ALL
SELECT 'staging_geolocation', COUNT(*)
FROM olist_ecommerce.staging_geolocation
UNION ALL
SELECT 'staging_order_reviews', COUNT(*)
FROM olist_ecommerce.staging_order_reviews
UNION ALL
SELECT 'staging_product_category_name_translation', COUNT(*)
FROM olist_ecommerce.staging_product_category_name_translation;