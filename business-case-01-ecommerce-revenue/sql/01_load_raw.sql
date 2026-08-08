-- =============================================================
-- 01_load_raw.sql
-- Loads the nine Olist CSVs from the volume into portfolio.raw
--
-- Source: Kaggle, Brazilian E-Commerce Public Dataset by Olist
-- Files staged at: /Volumes/portfolio/raw/files/
--
-- multiLine = true is REQUIRED. order_reviews contains customer
-- free text with embedded newlines; the default parser splits
-- those rows, producing 104,162 rows instead of 99,224.
-- See data-quality-notes.md, Finding 10.
--
-- Run order: this file first, then 02_staging.sql, then
-- 03_dimensions.sql, 04_facts.sql, 99_validation.sql
--
-- NOTE: verify the filenames below match your volume contents.
-- Run  LIST '/Volumes/portfolio/raw/files/';  to confirm.
-- =============================================================


-- -------------------------------------------------------------
-- Schemas
-- -------------------------------------------------------------

CREATE CATALOG IF NOT EXISTS portfolio;
USE CATALOG portfolio;

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS marts;


-- -------------------------------------------------------------
-- 1. orders — one row per order (expected 99,441)
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.raw.orders AS
SELECT * FROM read_files(
  '/Volumes/portfolio/raw/files/olist_orders_dataset.csv',
  format      => 'csv',
  header      => true,
  multiLine   => true,
  quote       => '"',
  escape      => '"',
  inferSchema => true
);


-- -------------------------------------------------------------
-- 2. order_items — one row per item within an order
--    Compound key: order_id + order_item_id (expected 112,650)
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.raw.order_items AS
SELECT * FROM read_files(
  '/Volumes/portfolio/raw/files/olist_order_items_dataset.csv',
  format      => 'csv',
  header      => true,
  multiLine   => true,
  quote       => '"',
  escape      => '"',
  inferSchema => true
);


-- -------------------------------------------------------------
-- 3. order_payments — one row per payment method per order
--    Compound key: order_id + payment_sequential (expected 103,886)
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.raw.order_payments AS
SELECT * FROM read_files(
  '/Volumes/portfolio/raw/files/olist_order_payments_dataset.csv',
  format      => 'csv',
  header      => true,
  multiLine   => true,
  quote       => '"',
  escape      => '"',
  inferSchema => true
);


-- -------------------------------------------------------------
-- 4. order_reviews — no unique key (expected 99,224)
--    THIS IS THE TABLE THAT REQUIRES multiLine = true.
--    Without it the load produces 104,162 malformed rows.
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.raw.order_reviews AS
SELECT * FROM read_files(
  '/Volumes/portfolio/raw/files/olist_order_reviews_dataset.csv',
  format      => 'csv',
  header      => true,
  multiLine   => true,
  quote       => '"',
  escape      => '"',
  inferSchema => true
);


-- -------------------------------------------------------------
-- 5. customers — one row per customer-order pairing
--    NOTE: customer_id is per-order; customer_unique_id is the
--    person. See data-quality-notes.md, Finding 4. (expected 99,441)
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.raw.customers AS
SELECT * FROM read_files(
  '/Volumes/portfolio/raw/files/olist_customers_dataset.csv',
  format      => 'csv',
  header      => true,
  multiLine   => true,
  quote       => '"',
  escape      => '"',
  inferSchema => true
);


-- -------------------------------------------------------------
-- 6. products — one row per product (expected 32,951)
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.raw.products AS
SELECT * FROM read_files(
  '/Volumes/portfolio/raw/files/olist_products_dataset.csv',
  format      => 'csv',
  header      => true,
  multiLine   => true,
  quote       => '"',
  escape      => '"',
  inferSchema => true
);


-- -------------------------------------------------------------
-- 7. sellers — one row per seller (expected 3,095)
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.raw.sellers AS
SELECT * FROM read_files(
  '/Volumes/portfolio/raw/files/olist_sellers_dataset.csv',
  format      => 'csv',
  header      => true,
  multiLine   => true,
  quote       => '"',
  escape      => '"',
  inferSchema => true
);


-- -------------------------------------------------------------
-- 8. geolocation — no unique key (expected 1,000,163)
--    Loaded for completeness but NOT used in the model.
--    See data-quality-notes.md, Finding 5.
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.raw.geolocation AS
SELECT * FROM read_files(
  '/Volumes/portfolio/raw/files/olist_geolocation_dataset.csv',
  format      => 'csv',
  header      => true,
  multiLine   => true,
  quote       => '"',
  escape      => '"',
  inferSchema => true
);


-- -------------------------------------------------------------
-- 9. category_name_translation — PT to EN lookup (expected 71)
--    Missing two categories present in products; corrected in
--    the staging layer, not here. See 02_staging.sql.
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.raw.category_name_translation AS
SELECT * FROM read_files(
  '/Volumes/portfolio/raw/files/product_category_name_translation.csv',
  format      => 'csv',
  header      => true,
  multiLine   => true,
  quote       => '"',
  escape      => '"',
  inferSchema => true
);


-- =============================================================
-- VERIFICATION
--
-- All nine counts must match. A mismatch on order_reviews
-- (104,162 instead of 99,224) means multiLine did not apply.
-- =============================================================

SELECT 'orders'                    AS table_name, count(*) AS actual, 99441   AS expected FROM portfolio.raw.orders
UNION ALL
SELECT 'order_items',              count(*), 112650  FROM portfolio.raw.order_items
UNION ALL
SELECT 'order_payments',           count(*), 103886  FROM portfolio.raw.order_payments
UNION ALL
SELECT 'order_reviews',            count(*), 99224   FROM portfolio.raw.order_reviews
UNION ALL
SELECT 'customers',                count(*), 99441   FROM portfolio.raw.customers
UNION ALL
SELECT 'products',                 count(*), 32951   FROM portfolio.raw.products
UNION ALL
SELECT 'sellers',                  count(*), 3095    FROM portfolio.raw.sellers
UNION ALL
SELECT 'geolocation',              count(*), 1000163 FROM portfolio.raw.geolocation
UNION ALL
SELECT 'category_name_translation', count(*), 71     FROM portfolio.raw.category_name_translation
ORDER BY table_name;