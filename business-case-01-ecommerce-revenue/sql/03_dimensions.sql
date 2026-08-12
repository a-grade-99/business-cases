-- =============================================================
-- 03_dimensions.sql
-- Builds the four dimension tables in portfolio.marts.
--
-- Dimensions are TABLES, not views: BI tools query them
-- repeatedly, so materialising is worth it here. Staging uses
-- views for the opposite reason.
--
-- NOTE: no dim_geography. The geolocation table has no unique
-- key (1,000,163 rows across 19,015 zip prefixes), 45% of
-- prefixes map to more than one city, and it supplies only
-- coordinates, which this analysis does not need. City and
-- state are attributes on dim_customer and dim_seller, taken
-- directly from those tables, both null-free.
-- See data-quality-notes.md, Finding 5.
--
-- Run after 02_staging.sql, before 04_facts.sql
-- =============================================================


-- -------------------------------------------------------------
-- 1. dim_date -- one row per calendar day
--
-- Range deliberately exceeds the analysis window. The dimension
-- covers every date present in the source; the scope filter
-- belongs in the fact tables.
--
-- Why a date table when Spark has month() built in: it supplies
-- dates with zero activity, so charts show real gaps instead of
-- skipping them, and it centralises the definition so every
-- chart's "quarter" means the same thing.
--
-- The derived table MUST be aliased (`dates`) or Spark throws
-- a parse error. Keep explode(sequence(...)) on one line.
--
-- Spark's dayofweek: 1 = Sunday, 7 = Saturday.
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.marts.dim_date AS
SELECT
  d                          AS date_key,
  year(d)                    AS year,
  quarter(d)                 AS quarter,
  month(d)                   AS month_number,
  date_format(d, 'MMMM')     AS month_name,
  date_format(d, 'yyyy-MM')  AS year_month,
  day(d)                     AS day_of_month,
  dayofweek(d)               AS day_of_week_number,
  date_format(d, 'EEEE')     AS day_of_week_name,
  CASE WHEN dayofweek(d) IN (1, 7) THEN true ELSE false END AS is_weekend
FROM (
  SELECT explode(sequence(date'2016-09-01', date'2018-12-31', interval 1 day)) AS d
) dates;


-- -------------------------------------------------------------
-- 2. dim_customer -- one row per customer-order pairing
--
-- Keyed on customer_id because that is what orders joins to.
-- customer_unique_id identifies the PERSON and rides along as
-- an attribute -- all customer counts use COUNTD on it, never
-- a row count. See data-quality-notes.md, Finding 4.
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.marts.dim_customer AS
SELECT
  customer_id,
  customer_unique_id,
  city,
  state
FROM portfolio.staging.customers;


-- -------------------------------------------------------------
-- 3. dim_product -- one row per product
--
-- LEFT JOIN, not JOIN. An inner join silently drops the 610
-- products with no category, and with them R$179,535 of
-- revenue -- exactly the failure Finding 6 exists to prevent.
--
-- coalesce() maps those to a single 'unknown' bucket so that
-- category-level totals still reconcile to headline revenue.
-- The bucket is labelled explicitly on the dashboard.
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.marts.dim_product AS
SELECT
  p.product_id,
  coalesce(p.category_name_pt, 'unknown') AS category_name_pt,
  coalesce(t.category_name_en, 'unknown') AS category_name_en,
  p.weight_g,
  p.length_cm,
  p.height_cm,
  p.width_cm
FROM portfolio.staging.products p
LEFT JOIN portfolio.staging.category_translation t
       ON p.category_name_pt = t.category_name_pt;


-- -------------------------------------------------------------
-- 4. dim_seller -- one row per seller
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.marts.dim_seller AS
SELECT
  seller_id,
  city,
  state
FROM portfolio.staging.sellers;


-- =============================================================
-- CHECKPOINT
--
-- EXPECTED:
--   dim_date      852 rows, 2016-09-01 to 2018-12-31
--   dim_customer  99,441 rows, 96,096 distinct customer_unique_id
--   dim_product   32,951 rows, 0 null category_name_en, 610 'unknown'
--   dim_seller    3,095 rows
-- =============================================================

SELECT 'dim_date'     AS dimension, count(*) AS rows, 852   AS expected FROM portfolio.marts.dim_date
UNION ALL
SELECT 'dim_customer', count(*), 99441 FROM portfolio.marts.dim_customer
UNION ALL
SELECT 'dim_product',  count(*), 32951 FROM portfolio.marts.dim_product
UNION ALL
SELECT 'dim_seller',   count(*), 3095  FROM portfolio.marts.dim_seller
ORDER BY dimension;


-- dim_product detail -- EXPECTED: 32951 / 0 / 610
SELECT
  count(*)                                                       AS total,
  sum(CASE WHEN category_name_en IS NULL THEN 1 ELSE 0 END)      AS null_english,
  sum(CASE WHEN category_name_en = 'unknown' THEN 1 ELSE 0 END)  AS unknown_bucket
FROM portfolio.marts.dim_product;


-- dim_customer detail -- EXPECTED: 99441 / 96096
SELECT
  count(*)                            AS rows,
  count(DISTINCT customer_unique_id)  AS distinct_people
FROM portfolio.marts.dim_customer;


-- dim_date weekend spot-check.
-- EXPECTED: Saturday and Sunday true, Monday-Friday false.
-- If Friday and Sunday come back true, the dayofweek numbering
-- assumption is wrong and is_weekend must be corrected.
SELECT date_key, day_of_week_name, is_weekend
FROM portfolio.marts.dim_date
WHERE date_key BETWEEN '2017-01-02' AND '2017-01-08'
ORDER BY date_key;