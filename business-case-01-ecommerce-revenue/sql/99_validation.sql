-- =============================================================
-- 99_validation.sql
--
-- Run this after ANY change to the dimensions or fact tables.
-- Every check has a known expected value, stated inline. A
-- mismatch means the model is wrong -- do not build or refresh
-- charts until it passes.
--
-- Expected values derived from metric-definitions.md section 7.
--
-- The check that matters most is #1. If fact revenue exceeds
-- source revenue, a join is fanning out -- duplicating rows and
-- inflating every number downstream. It is the most common
-- serious error in dimensional modelling and the hardest to
-- spot from a dashboard.
-- =============================================================


-- -------------------------------------------------------------
-- CHECK 1 -- Revenue reconciliation
--
-- The fact table must contain exactly the revenue present in
-- the filtered source. Not approximately. Exactly.
--
-- EXPECTED: source_revenue = fact_revenue = 13330627.12
-- -------------------------------------------------------------

SELECT
  (SELECT round(sum(i.price), 2)
   FROM portfolio.staging.order_items i
   JOIN portfolio.staging.orders o ON i.order_id = o.order_id
   WHERE o.status IN ('delivered','shipped')
     AND o.purchased_at >= '2017-01-01'
     AND o.purchased_at <  '2018-09-01')          AS source_revenue,
  (SELECT round(sum(revenue_net), 2)
   FROM portfolio.marts.fct_order_items)          AS fact_revenue,
  13330627.12                                     AS expected;


-- -------------------------------------------------------------
-- CHECK 2 -- Grain integrity
--
-- rows and distinct_keys MUST be equal. If rows is higher, the
-- fact table contains duplicates at its declared grain.
--
-- EXPECTED: 111054 / 111054 / 97308
-- -------------------------------------------------------------

SELECT
  count(*)                                              AS rows,
  count(DISTINCT concat(order_id, '-', order_item_id))  AS distinct_keys,
  count(DISTINCT order_id)                              AS distinct_orders
FROM portfolio.marts.fct_order_items;


-- -------------------------------------------------------------
-- CHECK 3 -- The two fact tables agree
--
-- fct_orders aggregates fct_order_items, so their revenue
-- totals must be identical. A difference means the order-grain
-- rollup lost or duplicated orders.
--
-- EXPECTED: both = 13330627.12
-- -------------------------------------------------------------

SELECT
  (SELECT round(sum(revenue_net), 2) FROM portfolio.marts.fct_order_items) AS items_total,
  (SELECT round(sum(revenue_net), 2) FROM portfolio.marts.fct_orders)      AS orders_total;


-- -------------------------------------------------------------
-- CHECK 4 -- No orphan keys
--
-- Every key in the fact table must resolve to a row in its
-- dimension. An orphan means that fact row vanishes from any
-- chart sliced by that dimension -- silently.
--
-- EXPECTED: all four columns = 0
-- -------------------------------------------------------------

SELECT
  (SELECT count(*) FROM portfolio.marts.fct_order_items f
   LEFT JOIN portfolio.marts.dim_product d ON f.product_id = d.product_id
   WHERE d.product_id IS NULL)   AS orphan_products,
  (SELECT count(*) FROM portfolio.marts.fct_order_items f
   LEFT JOIN portfolio.marts.dim_customer d ON f.customer_id = d.customer_id
   WHERE d.customer_id IS NULL)  AS orphan_customers,
  (SELECT count(*) FROM portfolio.marts.fct_order_items f
   LEFT JOIN portfolio.marts.dim_seller d ON f.seller_id = d.seller_id
   WHERE d.seller_id IS NULL)    AS orphan_sellers,
  (SELECT count(*) FROM portfolio.marts.fct_order_items f
   LEFT JOIN portfolio.marts.dim_date d ON f.date_key = d.date_key
   WHERE d.date_key IS NULL)     AS orphan_dates;


-- -------------------------------------------------------------
-- CHECK 5 -- Breakdown reconciles to total
--
-- Joining through dim_product must not change the total. This
-- is what catches the 'unknown' category bucket being dropped,
-- and it catches fan-out that CHECK 1 alone would miss.
--
-- EXPECTED: 13330627.12
-- -------------------------------------------------------------

SELECT round(sum(f.revenue_net), 2) AS revenue_via_category
FROM portfolio.marts.fct_order_items f
JOIN portfolio.marts.dim_product p ON f.product_id = p.product_id;


-- Same check through dim_customer / state.
-- EXPECTED: 13330627.12
SELECT round(sum(f.revenue_net), 2) AS revenue_via_state
FROM portfolio.marts.fct_order_items f
JOIN portfolio.marts.dim_customer c ON f.customer_id = c.customer_id;


-- -------------------------------------------------------------
-- CHECK 6 -- Metrics match metric-definitions.md
--
-- If these disagree with the definitions file, one of the two
-- is wrong. Find out which before building any charts.
--
-- EXPECTED (approximate):
--   orders        97,308
--   late_pct      8.1
--   median_days   10.2
--   p90_days      23.1
--   negative_pct  12.8
-- -------------------------------------------------------------

SELECT
  count(*)                                                          AS orders,
  round(100.0 * sum(CASE WHEN is_late THEN 1 ELSE 0 END)
              / sum(CASE WHEN is_late IS NOT NULL THEN 1 ELSE 0 END), 1) AS late_pct,
  round(percentile(delivery_days, 0.5), 1)                          AS median_days,
  round(percentile(delivery_days, 0.9), 1)                          AS p90_days,
  round(100.0 * sum(CASE WHEN is_negative_review THEN 1 ELSE 0 END)
              / sum(CASE WHEN is_negative_review IS NOT NULL THEN 1 ELSE 0 END), 1) AS negative_pct
FROM portfolio.marts.fct_orders;


-- -------------------------------------------------------------
-- CHECK 7 -- The headline finding
--
-- Not a validation check as such, but worth keeping here: this
-- is the result the dashboard is built to communicate, and if
-- it ever stops reproducing, something upstream has changed.
--
-- EXPECTED: negative review rate rises from ~7% at 0-3 days to
-- ~66% at 31+ days. Flat to roughly 14 days, then a cliff.
-- -------------------------------------------------------------

SELECT
  CASE WHEN delivery_days <=  3 THEN '0-3'
       WHEN delivery_days <=  7 THEN '4-7'
       WHEN delivery_days <= 14 THEN '8-14'
       WHEN delivery_days <= 21 THEN '15-21'
       WHEN delivery_days <= 30 THEN '22-30'
       ELSE '31+' END                                              AS delivery_bucket,
  count(*)                                                         AS orders,
  round(100.0 * sum(CASE WHEN is_negative_review THEN 1 ELSE 0 END)
              / sum(CASE WHEN is_negative_review IS NOT NULL THEN 1 ELSE 0 END), 1) AS negative_pct
FROM portfolio.marts.fct_orders
WHERE delivery_days IS NOT NULL
GROUP BY 1
ORDER BY min(delivery_days);