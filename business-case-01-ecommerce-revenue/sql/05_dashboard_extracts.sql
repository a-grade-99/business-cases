-- Revenue By Category State and Month
SELECT p.category_name_en,
       c.state,
       d.year_month,
       sum(f.revenue_net)                AS revenue_net,
       sum(f.freight_cost)               AS freight_cost,
       sum(f.contribution_after_freight) AS contribution_after_freight,
       count(*)                          AS items
FROM portfolio.marts.fct_order_items f
JOIN portfolio.marts.dim_product  p ON f.product_id  = p.product_id
JOIN portfolio.marts.dim_customer c ON f.customer_id = c.customer_id
JOIN portfolio.marts.dim_date     d ON f.date_key    = d.date_key
GROUP BY 1, 2, 3;

-- Delivery by State and Month
SELECT c.state,
       d.year_month,
       count(*)                                                          AS orders,
       sum(CASE WHEN o.is_late THEN 1 ELSE 0 END)                        AS late_orders,
       sum(CASE WHEN o.is_late IS NOT NULL THEN 1 ELSE 0 END)            AS delivered_orders,
       percentile(o.delivery_days, 0.5)                                  AS median_days,
       percentile(o.delivery_days, 0.9)                                  AS p90_days,
       sum(CASE WHEN o.is_negative_review THEN 1 ELSE 0 END)             AS negative_reviews,
       sum(CASE WHEN o.is_negative_review IS NOT NULL THEN 1 ELSE 0 END) AS reviewed_orders,
       sum(o.revenue_net)                                                AS revenue_net,
       sum(o.freight_cost)                                               AS freight_cost
FROM portfolio.marts.fct_orders o
JOIN portfolio.marts.dim_customer c ON o.customer_id = c.customer_id
JOIN portfolio.marts.dim_date     d ON o.date_key    = d.date_key
GROUP BY 1, 2;

-- Delivery Buckets
SELECT
  CASE WHEN delivery_days <=  3 THEN '0-3'
       WHEN delivery_days <=  7 THEN '4-7'
       WHEN delivery_days <= 14 THEN '8-14'
       WHEN delivery_days <= 21 THEN '15-21'
       WHEN delivery_days <= 30 THEN '22-30'
       ELSE '31+' END                                              AS delivery_bucket,
  count(*)                                                         AS orders,
  sum(CASE WHEN is_negative_review THEN 1 ELSE 0 END)              AS negative_reviews,
  sum(CASE WHEN is_negative_review IS NOT NULL THEN 1 ELSE 0 END)  AS reviewed_orders
FROM portfolio.marts.fct_orders
WHERE delivery_days IS NOT NULL
GROUP BY 1
ORDER BY min(delivery_days);