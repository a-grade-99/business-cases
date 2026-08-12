-- =============================================================
-- 04_facts.sql
-- Builds the two fact tables in portfolio.marts.
--
-- WHY TWO FACT TABLES AT DIFFERENT GRAINS:
--
-- Revenue, freight and contribution are ITEM-level measures.
-- Delivery time, lateness and review score are ORDER-level --
-- an order has one delivery time regardless of how many items
-- it contains.
--
-- Putting order-level measures on an item-grain table would
-- weight every average by basket size: a 4-item order would
-- count four times toward "average delivery days". Splitting
-- the facts avoids that.
--
--   fct_order_items -- one row per item  (111,054 rows)
--   fct_orders      -- one row per order  (97,308 rows)
--
-- SCOPE (applied here, not in staging):
--   status IN ('delivered','shipped')
--   purchased_at >= 2017-01-01 AND < 2018-09-01
-- See metric-definitions.md section 1.
--
-- Run after 03_dimensions.sql
-- =============================================================


-- -------------------------------------------------------------
-- 1. fct_order_items -- grain: one row per item within an order
--
-- Compound key: order_id + order_item_id. order_item_id alone
-- is a sequence number within each order (only 21 distinct
-- values), not a global identifier. See Finding 1.
--
-- Date bound is < '2018-09-01', NOT <= '2018-08-31'. The latter
-- truncates at midnight and silently drops a day of orders.
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.marts.fct_order_items AS
SELECT
  i.order_id,
  i.order_item_id,
  i.product_id,
  i.seller_id,
  o.customer_id,
  cast(o.purchased_at AS date)  AS date_key,
  i.price                       AS revenue_net,
  i.freight_value               AS freight_cost,
  i.price + i.freight_value     AS revenue_gross,
  i.price - i.freight_value     AS contribution_after_freight
FROM portfolio.staging.order_items i
JOIN portfolio.staging.orders o
  ON i.order_id = o.order_id
WHERE o.status IN ('delivered', 'shipped')
  AND o.purchased_at >= '2017-01-01'
  AND o.purchased_at <  '2018-09-01';


-- -------------------------------------------------------------
-- 2. fct_orders -- grain: one row per order
--
-- Three things to understand here:
--
-- (a) reviews_deduped applies the deduplication rule from
--     Finding 3: one review per order, most recent first.
--     547 orders carry multiple reviews and 789 review_ids
--     appear against multiple orders. The `, review_id`
--     tiebreak makes the result deterministic -- without it,
--     two reviews written in the same second could resolve
--     differently on different runs.
--     The inner subquery MUST be aliased (`ranked`).
--
-- (b) JOIN item_totals, not LEFT JOIN. This deliberately drops
--     the 775 orders with no line items -- they generated no
--     revenue and belong in neither fact table. See Finding 9.
--
-- (c) The CASE expressions return NULL for shipped-but-not-
--     delivered orders rather than a wrong number. Nulls are
--     excluded from averages automatically, which is correct.
--
-- Column names below match the staging layer: `score` and
-- `creation_at` in staging.order_reviews, surfaced here as
-- review_score since "score" alone is ambiguous outside that
-- table.
-- -------------------------------------------------------------

CREATE OR REPLACE TABLE portfolio.marts.fct_orders AS
WITH reviews_deduped AS (
  SELECT order_id, score
  FROM (
    SELECT order_id,
           score,
           row_number() OVER (PARTITION BY order_id
                              ORDER BY creation_at DESC, review_id) AS rn
    FROM portfolio.staging.order_reviews
  ) ranked
  WHERE rn = 1
),
item_totals AS (
  SELECT order_id,
         sum(revenue_net)                AS revenue_net,
         sum(freight_cost)               AS freight_cost,
         sum(contribution_after_freight) AS contribution_after_freight,
         count(*)                        AS item_count
  FROM portfolio.marts.fct_order_items
  GROUP BY order_id
)
SELECT
  o.order_id,
  o.customer_id,
  cast(o.purchased_at AS date) AS date_key,
  o.status,
  t.revenue_net,
  t.freight_cost,
  t.contribution_after_freight,
  t.item_count,
  CASE WHEN o.status = 'delivered' AND o.delivered_at IS NOT NULL
       THEN datediff(o.delivered_at, o.purchased_at) END  AS delivery_days,
  CASE WHEN o.status = 'delivered' AND o.delivered_at IS NOT NULL
       THEN o.delivered_at > o.estimated_delivery_at END  AS is_late,
  r.score                                                 AS review_score,
  CASE WHEN r.score <= 2 THEN true
       WHEN r.score IS NOT NULL THEN false END            AS is_negative_review
FROM portfolio.staging.orders o
JOIN item_totals t
  ON o.order_id = t.order_id
LEFT JOIN reviews_deduped r
  ON o.order_id = r.order_id
WHERE o.status IN ('delivered', 'shipped')
  AND o.purchased_at >= '2017-01-01'
  AND o.purchased_at <  '2018-09-01';


-- =============================================================
-- CHECKPOINT
--
-- EXPECTED:
--   fct_order_items  111,054 rows
--   fct_orders        97,308 rows
--
-- Full validation is in 99_validation.sql -- run it now.
-- =============================================================

SELECT 'fct_order_items' AS fact_table, count(*) AS rows, 111054 AS expected
FROM portfolio.marts.fct_order_items
UNION ALL
SELECT 'fct_orders', count(*), 97308
FROM portfolio.marts.fct_orders
ORDER BY fact_table;