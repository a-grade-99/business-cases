-- =============================================================
-- 02_staging.sql
-- Renames and retypes the raw tables. One view per source table.
--
-- RULES FOR THIS LAYER:
--   1. Rename columns to a consistent convention
--   2. Cast types correctly (raw timestamps arrive as strings)
--   3. Fix unambiguous source defects
-- =============================================================


-- -------------------------------------------------------------
-- 1. orders
--
-- carrier_handover_at renamed from order_delivered_carrier_date:
-- the original reads as "delivered to carrier" and is easily
-- misread as the customer delivery date.
-- -------------------------------------------------------------

CREATE OR REPLACE VIEW portfolio.staging.orders AS
SELECT
  order_id,
  customer_id,
  order_status                                     AS status,
  cast(order_purchase_timestamp      AS timestamp) AS purchased_at,
  cast(order_approved_at             AS timestamp) AS approved_at,
  cast(order_delivered_carrier_date  AS timestamp) AS carrier_handover_at,
  cast(order_delivered_customer_date AS timestamp) AS delivered_at,
  cast(order_estimated_delivery_date AS timestamp) AS estimated_delivery_at
FROM portfolio.raw.orders;


-- -------------------------------------------------------------
-- 2. order_items
--
-- decimal(10,2) rather than float: floating-point arithmetic
-- accumulates rounding error across 111k rows, and the
-- validation checks compare exact totals.
-- -------------------------------------------------------------

CREATE OR REPLACE VIEW portfolio.staging.order_items AS
SELECT
  order_id,
  order_item_id,
  product_id,
  seller_id,
  cast(shipping_limit_date AS timestamp)     AS shipping_limit_at,
  cast(price               AS decimal(10,2)) AS price,
  cast(freight_value       AS decimal(10,2)) AS freight_value
FROM portfolio.raw.order_items;


-- -------------------------------------------------------------
-- 3. order_payments
-- -------------------------------------------------------------

CREATE OR REPLACE VIEW portfolio.staging.order_payments AS
SELECT
  order_id,
  payment_sequential,
  payment_type,
  payment_installments,
  cast(payment_value AS decimal(10,2)) AS payment_value
FROM portfolio.raw.order_payments;


-- -------------------------------------------------------------
-- 4. order_reviews
--
-- All 99,224 rows retained. The deduplication rule (one review
-- per order, most recent by created_at) is business logic and
-- is applied in the marts layer, not here.
-- See data-quality-notes.md, Finding 3.
-- -------------------------------------------------------------

CREATE OR REPLACE VIEW portfolio.staging.order_reviews AS
SELECT
  review_id,
  order_id,
  review_score,
  review_comment_title                       AS comment_title,
  review_comment_message                     AS comment_message,
  cast(review_creation_date    AS timestamp) AS created_at,
  cast(review_answer_timestamp AS timestamp) AS answered_at
FROM portfolio.raw.order_reviews;


-- -------------------------------------------------------------
-- 5. customers
--
-- Both identifiers retained. customer_id joins to orders;
-- customer_unique_id is the person and is the business key for
-- dim_customer. See data-quality-notes.md, Finding 4.
-- -------------------------------------------------------------

CREATE OR REPLACE VIEW portfolio.staging.customers AS
SELECT
  customer_id,
  customer_unique_id,
  customer_zip_code_prefix AS zip_code_prefix,
  customer_city            AS city,
  customer_state           AS state
FROM portfolio.raw.customers;


-- -------------------------------------------------------------
-- 6. products
--
-- category_name_pt makes the language explicit so category_name_en
-- in marts is unmistakable.
--
-- product_name_lenght, product_description_lenght and
-- product_photos_qty are dropped: unused, and the misspelled
-- "lenght" in the source would otherwise propagate downstream.
-- -------------------------------------------------------------

CREATE OR REPLACE VIEW portfolio.staging.products AS
SELECT
  product_id,
  product_category_name AS category_name_pt,
  product_weight_g      AS weight_g,
  product_length_cm     AS length_cm,
  product_height_cm     AS height_cm,
  product_width_cm      AS width_cm
FROM portfolio.raw.products;


-- -------------------------------------------------------------
-- 7. sellers
-- -------------------------------------------------------------

CREATE OR REPLACE VIEW portfolio.staging.sellers AS
SELECT
  seller_id,
  seller_zip_code_prefix AS zip_code_prefix,
  seller_city            AS city,
  seller_state           AS state
FROM portfolio.raw.sellers;


-- -------------------------------------------------------------
-- 8. category_translation
--
-- THE ONE VIEW THAT CHANGES ROW COUNT: 71 -> 73.
--
-- Two categories present in products have no entry in the
-- source translation table, affecting 13 product rows. Filling
-- a known source gap is legitimate staging work; without it
-- these become null on join in dim_product.
--
-- pc_gamer translates to itself: already English.
-- See data-quality-notes.md, Referential integrity section.
-- -------------------------------------------------------------

CREATE OR REPLACE VIEW portfolio.staging.category_translation AS
SELECT
  product_category_name         AS category_name_pt,
  product_category_name_english AS category_name_en
FROM portfolio.raw.category_name_translation

UNION ALL
SELECT 'pc_gamer', 'pc_gamer'

UNION ALL
SELECT 'portateis_cozinha_e_preparadores_de_alimentos',
       'portable_kitchen_and_food_preparers';


-- -------------------------------------------------------------
-- 9. geolocation — DELIBERATELY NOT STAGED
--
-- No unique key: 1,000,163 rows across 19,015 zip prefixes
-- (~52 rows per prefix, max 1,146). 45% of prefixes map to more
-- than one city, 8 map to more than one state, and 42 rows have
-- coordinates outside Brazil's bounds.
--
-- Provides only coordinates, which this analysis does not
-- require. City and state come from customers and sellers,
-- both null-free.
--
-- If added later: aggregate to one row per prefix (median
-- lat/lng, modal city/state) and exclude out-of-bounds rows
-- first, or fact rows will multiply ~52x.
--
-- See data-quality-notes.md, Finding 5.
-- -------------------------------------------------------------


-- =============================================================
-- VERIFICATION
--
-- Every row must match except category_translation (71 -> 73).
-- Any other mismatch means business logic leaked into staging.
-- =============================================================

SELECT 'orders' AS table_name,
       (SELECT count(*) FROM portfolio.raw.orders)     AS raw_rows,
       (SELECT count(*) FROM portfolio.staging.orders) AS staging_rows
UNION ALL
SELECT 'order_items',
       (SELECT count(*) FROM portfolio.raw.order_items),
       (SELECT count(*) FROM portfolio.staging.order_items)
UNION ALL
SELECT 'order_payments',
       (SELECT count(*) FROM portfolio.raw.order_payments),
       (SELECT count(*) FROM portfolio.staging.order_payments)
UNION ALL
SELECT 'order_reviews',
       (SELECT count(*) FROM portfolio.raw.order_reviews),
       (SELECT count(*) FROM portfolio.staging.order_reviews)
UNION ALL
SELECT 'customers',
       (SELECT count(*) FROM portfolio.raw.customers),
       (SELECT count(*) FROM portfolio.staging.customers)
UNION ALL
SELECT 'products',
       (SELECT count(*) FROM portfolio.raw.products),
       (SELECT count(*) FROM portfolio.staging.products)
UNION ALL
SELECT 'sellers',
       (SELECT count(*) FROM portfolio.raw.sellers),
       (SELECT count(*) FROM portfolio.staging.sellers)
UNION ALL
SELECT 'category_translation (expect 71 -> 73)',
       (SELECT count(*) FROM portfolio.raw.category_name_translation),
       (SELECT count(*) FROM portfolio.staging.category_translation)
ORDER BY table_name;


-- -------------------------------------------------------------
-- Confirm the timestamp casts actually applied.
-- All five date columns must report `timestamp`, not `string`.
-- -------------------------------------------------------------

-- DESCRIBE portfolio.staging.orders;


-- -------------------------------------------------------------
-- Spot-check that the timestamps behave as timestamps.
-- Note: Spark's datediff is datediff(end, start) -- the
-- argument order is reversed from T-SQL.
-- -------------------------------------------------------------

SELECT order_id,
       purchased_at,
       delivered_at,
       datediff(delivered_at, purchased_at) AS delivery_days
FROM portfolio.staging.orders
WHERE delivered_at IS NOT NULL
LIMIT 5;