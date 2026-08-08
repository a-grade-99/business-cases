## Metric Definitions — Case 1: Olist Revenue & Delivery Analysis

**Purpose**: This file defines every metric used in the analysis and dashboard. Any two analysts reading it should produce identical numbers from the same source data.
> **Decisions marked ⚑ are judgement calls with defensible alternatives.** The reasoning is stated in each case.

---

## 1. Scope

All metrics below are computed within this scope unless explicitly stated otherwise.

| Parameter | Value | Rationale |
|---|---|---|
| **Time period** | 2017-01-01 to 2018-08-31 | 20 complete months. The raw range extends to 2016-09 and 2018-10, but those months contain 4–324 orders each, and November 2016 contains none. Including them produces artificial flat lines and an apparent 99.8% collapse at the end. See Finding 8. |
| **Date basis** | `order_purchase_timestamp` ⚑ | The analysis concerns demand — what sells, where. Purchase date is when demand occurred, and it is present on every order. Delivery date would shift monthly totals materially (Aug 2018: 6,512 purchased vs 8,314 delivered). |
| **Order status** | `delivered`, `shipped` ⚑ | Goods have physically moved and revenue is realised or all but certain. Excludes `canceled` and `unavailable` (never fulfilled) and `invoiced`/`processing`/`created`/`approved` (not yet shipped). |
| **Grain** | Order-item | An order can contain multiple items with different products, sellers, prices, and freight. Order grain would make category and seller analysis impossible. |

**Scope totals:**

| | Count |
|---|---|
| Orders | 97,308 (of 99,441) |
| Order items | 111,054 (of 112,650) |
| Distinct customers | 94,136 |
| States represented | 27 |

---

## 2. Revenue metrics

### `revenue_net` — primary revenue measure

**Definition:** `sum(order_items.price)` across all in-scope order items.

**Excludes:** freight, and all orders outside the scope defined above.

**Value in scope:** R$13,330,627.12

**Why this is the headline:** freight is a pass-through to the carrier, not marketplace revenue. Including it would inflate the figure by 16.6% and misrepresent what the business actually transacted.

**Used for:** all category and regional revenue comparisons; the headline dashboard figure.

---

### `revenue_gross` — customer-facing total

**Definition:** `sum(order_items.price + order_items.freight_value)`.

**Value in scope:** R$15,548,777.64

**Used for:** only where the question is genuinely about total customer spend. Not used in category or regional breakdowns.

⚠️ Never present `revenue_gross` and `revenue_net` on the same chart without labelling both. The 16.6% gap is large enough to mislead.

---

### `freight_cost`

**Definition:** `sum(order_items.freight_value)`.

**Value in scope:** R$2,218,150.52 — 16.64% of `revenue_net`.

---

### `contribution_after_freight`

**Definition:** `sum(order_items.price - order_items.freight_value)`.

**Value in scope:** R$11,112,476.60

> ### ⚠️ This is NOT margin
>
> The dataset contains **no cost-of-goods data**. True gross margin cannot be computed from Olist and is not presented anywhere in this analysis.
>
> `contribution_after_freight` measures one thing only: how much of an item's price is absorbed by shipping it. It is useful for comparing categories and regions where freight burden differs — a heavy, low-value product in a distant state may generate revenue while contributing far less than its price suggests.
>
> Any chart using this metric is labelled "contribution after freight," never "margin" or "profit."

**Used for:** dashboard question 1 (which categories are worth serving) and question 2 (which regions are expensive to serve).

---

## 3. Delivery metrics

**Population:** in-scope orders with status `delivered` and a non-null `order_delivered_customer_date`.

**Exclusions:** 8 orders with status `delivered` but no delivery timestamp (Finding 7). No negative intervals remain after applying the scope filter.

**Orders measured:** 96,203

---

### `delivery_days`

**Definition:** `order_delivered_customer_date − order_purchase_timestamp`, expressed in days.

**Reported as:** median and p90. ⚑

| Statistic | Value |
|---|---|
| Median (p50) | 10.2 days |
| p90 | 23.1 days |
| Mean | 12.5 days |

**Why not the mean:** the distribution is right-skewed, with a long tail reaching 209 days. The mean (12.5) sits above the median (10.2) because outliers drag it up, so it describes no typical customer's experience. The median states what half of customers experienced; p90 states what the worst-served tenth experienced. Together they convey both the norm and the tail.

**The mean is not shown on any chart.**

---

### `is_late` / `on_time_rate`

**Definition:**
```
is_late      = order_delivered_customer_date > order_estimated_delivery_date
on_time_rate = 1 − (late orders ÷ delivered orders)
```

**Value in scope:** 91.9% on time. 7,822 orders delivered late.

**Why this metric:** it measures performance against the promise the customer was given, rather than against an arbitrary duration threshold. A 20-day delivery is not a failure if 25 days were promised.

---

## 4. Satisfaction metrics

**Deduplication rule:** one review per order, taking the most recent by `review_creation_date`. Required because 547 orders carry multiple reviews and 789 `review_id` values appear against multiple orders (Finding 3). Applied before any aggregation.

**Reviews matched to in-scope delivered orders:** 95,560

---

### `negative_review_rate` — primary satisfaction measure

**Definition:** share of reviews with `review_score` of 1 or 2.

**Value in scope:** 12.8%

**Why not mean score:** 57.8% of all reviews are 5-star and 77% are 4 or 5. With that concentration at the ceiling, the mean has poor discriminating power — it moves very little even when outcomes differ sharply.

The difference is stark in practice:

| Delivery outcome | Mean score | Negative review rate |
|---|---|---|
| On time (87,902 orders) | 4.29 | **9.2%** |
| Late (7,658 orders) | 2.57 | **54.1%** |

The mean shows a 1.7-point difference. The negative review rate shows a **5.9× difference**. The second is both more legible and more actionable.

**Used for:** dashboard question 3.

---

## 5. Dimension definitions

### `customer`

**Key:** `customers.customer_unique_id` — **not** `customer_id`.

`customer_id` identifies a customer-order pairing; `customer_unique_id` identifies the person. In scope, these differ: 97,308 vs 94,136. Using the wrong one would overstate the customer base by 3.4% and make repeat-purchase analysis impossible. See Finding 4.

---

### `region`

**Key:** `customers.customer_state` — 27 values (26 states plus the Federal District).

City is not used: 4,119 distinct values is unusable in a chart. The `geolocation` table is not used at all — it has no unique key, multiplies rows ~52×, and adds only coordinates, which are not required. `customers` and `sellers` carry state directly with zero nulls. See Finding 5.

---

### `category`

**Key:** `products.product_category_name`, translated to English via `category_name_translation`.

**Null handling:** 610 products have no category, representing R$179,535.28 (1.32% of revenue). These are mapped to a single `unknown` bucket via `coalesce()` rather than dropped, so category totals reconcile to headline revenue. The bucket is labelled explicitly on the dashboard so it is not read as a real category. See Finding 6.

**Missing translations:** `pc_gamer` → "PC Gamer" and `portateis_cozinha_e_preparadores_de_alimentos` → "Portable Kitchen and Food Preparers", added manually in the staging layer (13 product rows affected).

---

### `date`

**Key:** date derived from `order_purchase_timestamp`, joined to `dim_date`.

All time-series aggregation uses `dim_date` attributes rather than inline date functions, so that "month" and "quarter" are defined identically across every chart.

---

## 6. Metrics deliberately not used

Recording these prevents re-litigating decisions later and shows the choices were considered.

| Metric | Why not |
|---|---|
| Gross margin / profit | No cost-of-goods data exists. Cannot be computed. |
| Mean delivery days | Distribution is right-skewed; median and p90 used instead. |
| Mean review score | 58% ceiling effect; negative review rate used instead. |
| Revenue by delivery date | Scope uses purchase date; mixing bases would double-count. |
| City-level regional analysis | 4,119 distinct values; state level used instead. |
| Payment-based revenue | `order_items` is the source of truth — it attributes revenue to products and sellers, which `order_payments` cannot. The two reconcile to 0.018%. |

---

## 7. Reconciliation checks

These must hold in the marts layer. Implemented in `sql/99_validation.sql`.

| Check | Expected |
|---|---|
| `sum(revenue_net)` in `fct_order_items` | R$13,330,627.12 |
| Row count in `fct_order_items` | 111,054 |
| Distinct orders in `fct_order_items` | 97,308 |
| Sum of category-level revenue | equals `revenue_net` exactly |
| Sum of state-level revenue | equals `revenue_net` exactly |
| Orphan keys in fact table | 0 |

The two "sum of breakdown equals total" checks are the ones that catch the `unknown` bucket being accidentally dropped and joins fanning out. Run them after every model change.