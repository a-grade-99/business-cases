# Data Quality Notes — Olist E-Commerce Dataset

**Profiled:** 06–08 Aug 2026
**Source:** Kaggle, Brazilian E-Commerce Public Dataset by Olist
**Purpose:** Document data quality issues found before modelling, and the decisions made about each.

---

## Summary

The dataset is in good condition overall. Referential integrity is intact — every foreign key in every child table resolves to its parent, with no orphaned records. Key uniqueness behaves as expected once compound keys are recognised. The three issues that most affect the analysis are: **(1)** 610 products carry no category, representing 1.32% of revenue that would silently disappear from any category breakdown; **(2)** the usable date range is materially narrower than the raw minimum and maximum suggest, since the first four months and last two months are near-empty; and **(3)** `order_reviews` has no unique key, so a review-level join requires an explicit deduplication rule.

One issue was introduced during ingestion rather than present in the source: the initial CSV load split rows on embedded newlines in free-text review fields, producing 104,162 rows against an expected 99,224. Corrected by enabling multiline parsing. See Finding 10.

---

## Table structure

| Table | Rows | Key | Notes |
|---|---|---|---|
| orders | 99,441 | `order_id` | Unique ✓ |
| order_items | 112,650 | `order_id` + `order_item_id` | Compound — see Finding 1 |
| order_payments | 103,886 | `order_id` + `payment_sequential` | Compound — see Finding 2 |
| order_reviews | 99,224 | none | See Finding 3 |
| customers | 99,441 | `customer_id` | Unique ✓ — but see Finding 4 |
| products | 32,951 | `product_id` | Unique ✓ |
| sellers | 3,095 | `seller_id` | Unique ✓ |
| geolocation | 1,000,163 | none | See Finding 5 |
| category_name_translation | 71 | `product_category_name` | Unique ✓ |

---

## Expected nulls (no action required)

Nulls that have a legitimate explanation and require no handling decision.

### orders — delivery timestamps

Null rates were cross-tabulated against `order_status` to confirm the missingness is explained by order lifecycle stage rather than data loss.

| Column | Nulls | % | Explanation |
|---|---|---|---|
| `order_approved_at` | 160 | 0.16% | Concentrated in `canceled` (141) and `created` (5) — orders that never reached approval. |
| `order_delivered_carrier_date` | 1,783 | 1.79% | Concentrated in `unavailable` (609), `canceled` (550), `invoiced` (314), `processing` (301) — orders never handed to a carrier. |
| `order_delivered_customer_date` | 2,965 | 2.98% | Concentrated in `shipped` (1,107), `canceled` (619), `unavailable` (609), `invoiced` (314), `processing` (301) — orders not yet or never delivered. |

The cross-tabulation confirms the pattern, with one exception that does **not** fit and is recorded separately as Finding 7.

### order_reviews — free-text fields

| Column | Nulls | % | Explanation |
|---|---|---|---|
| `review_comment_title` | 87,656 | 88.34% | Most reviewers submit a score without a written title. Not used in current analysis. |
| `review_comment_message` | 58,247 | 58.70% | Most reviewers submit a score without written feedback. Not used in current analysis. |

### products — physical attributes

| Column | Nulls | % | Explanation |
|---|---|---|---|
| `product_weight_g` | 2 | <0.1% | Physical attributes missing for two listings. Not used in current analysis; would need revisiting if freight cost drivers were analysed. |
| `product_length_cm` | 2 | <0.1% | As above. |
| `product_height_cm` | 2 | <0.1% | As above. |
| `product_width_cm` | 2 | <0.1% | As above. |
| `product_name_lenght` | 610 | 1.85% | Null in exactly the same rows as `product_category_name` (see Finding 6) — these are listings with no descriptive metadata at all. Not used in current analysis. |
| `product_description_lenght` | 610 | 1.85% | As above. |
| `product_photos_qty` | 610 | 1.85% | As above. |

### Tables with no nulls

Verified across all columns, including `trim() = ''` checks on text columns:

**order_items**, **order_payments**, **customers**, **sellers**, **geolocation**, **category_name_translation** — no nulls or blank strings in any column.

---

## Findings

### 1. order_items requires a compound key

**What:** `order_id` alone is not unique (98,666 distinct values across 112,650 rows), because an order can contain multiple items. `order_item_id` alone is not unique either — it holds only 21 distinct values, because it is a **sequence number within each order** (1, 2, 3…), not a global identifier. The combination `order_id` + `order_item_id` is unique across all 112,650 rows.

**Impact:** Joining on `order_item_id` alone would match every "item 1" against every other "item 1" across the dataset, catastrophically inflating row counts and revenue.

**Decision:** Treat `order_id` + `order_item_id` as the compound key. Fact table grain is order-item, matching this key.

---

### 2. order_payments requires a compound key

**What:** Same structure as Finding 1. `order_id` is not unique (99,440 distinct across 103,886 rows) because an order can be split across multiple payment methods — commonly a credit card plus one or more vouchers. `payment_sequential` holds 29 distinct values and counts within the order. The pair is unique.

**Impact:** Beyond the join risk, this table sits at a **different grain** from `order_items`. Joining the two directly produces a cartesian fan-out: an order with 2 items and 3 payments yields 6 rows and inflates both revenue and payment totals. Each table must be aggregated to order level *before* being combined.

**Decision:** Treat `order_id` + `payment_sequential` as the compound key. Never join `order_items` to `order_payments` directly.

---

### 3. order_reviews has no unique key

**What:** Neither column identifies a row on its own. Across 99,224 rows there are 98,410 distinct `review_id` values and 98,673 distinct `order_id` values.

**Scale:**
- 547 orders carry more than one review (1,098 rows, 1.11% of the table). Maximum is 3 reviews for a single order.
- 789 `review_id` values appear more than once (1,603 rows, 1.62% of the table). Maximum is 3 rows sharing one `review_id`.

**Likely cause:** Two distinct mechanisms. Multiple reviews per order suggest a customer submitted more than one review over time. Repeated `review_id` values across different orders suggest a single review submitted against a multi-order purchase, with the review record duplicated per order.

**Impact:** Affects dashboard question 3 (delivery performance vs. review score). Without a rule, an order with two differing scores would be double-counted and would distort the average score against delivery time.

**Decision:** Deduplicate to one review per order, taking the most recent by `review_creation_date`. Recorded in `metric-definitions.md`. The affected proportion is small enough (~1%) that the choice of rule has negligible effect on aggregate results.

---

### 4. customers has two identifier columns with different meanings

**What:** `customer_id` is unique per row (99,441 distinct). `customer_unique_id` has only 96,096 distinct values — it identifies the **person**, while `customer_id` identifies a person-order pairing. 3,345 customers placed more than one order.

**Impact:** Using the wrong column silently changes what "number of customers" means. Counting `customer_id` counts orders, not people, and would overstate the customer base by ~3.5%.

**Decision:** Build `dim_customer` on `customer_unique_id` as the business key, retaining `customer_id` as the join key to `orders`. Any customer-count metric uses `customer_unique_id`.

---

### 5. geolocation has no unique key and duplicates city/state mappings

**What:** 1,000,163 rows map to only 19,015 distinct zip code prefixes — an average of 52.6 rows per prefix, and up to 1,146 for a single prefix. Each row is an individual coordinate point, not a location record.

**Scale:** Beyond the row multiplication, 8,556 zip prefixes (45.0% of prefixes) map to more than one city name, and 8 map to more than one state — meaning the table is not internally consistent as a lookup. Additionally, 42 rows have coordinates falling outside Brazil's geographic bounds (latitude range extends to +45.07, longitude to +121.11).

**Impact:** Joining this table directly to `customers` or `sellers` would multiply fact rows by ~52x.

**Decision:** **Scope this table out of the current model.** `customers` and `sellers` already carry `city` and `state` directly and with no nulls, which satisfies all regional analysis requirements for dashboard question 2. Geolocation would only add mapping coordinates, which are not required. If added later, it must be aggregated to one row per prefix — taking the median latitude and longitude and the modal city/state — and the out-of-bounds rows excluded first.

---

### 6. Products with no category

**What:** `product_category_name` is null for a subset of products. These products appear in real orders with real prices, so they carry revenue that must be accounted for somewhere in any category-level breakdown.

**Scale:** 610 products (1.85% of the products table), appearing in 1,603 order items and representing R$179,535.28 in revenue — 1.32% of the R$13,591,643.70 total (measured as `sum(price)`, excluding freight). Including freight: R$207,705.09 of R$15,843,553.24, or 1.31%.

**Likely cause:** Category was optional or unvalidated at listing time; sellers could publish without selecting one. The same 610 rows are also null for `product_name_lenght`, `product_description_lenght`, and `product_photos_qty`, indicating these listings were created with no descriptive metadata whatsoever — consistent with bulk import or an incomplete listing flow.

**Impact:** Affects dashboard question 1 (revenue and margin by category). Dropping these products would understate total revenue and make the category chart fail to reconcile with the headline revenue figure.

**Decision:** Map to a single `unknown` category rather than excluding. This keeps category-level totals reconciling to overall revenue. The `unknown` bucket is labelled explicitly on the dashboard so it isn't mistaken for a real category. Applied in `dim_product` via `coalesce()`.

---

### 7. Impossible date sequences

**What:** The four order timestamps should occur in the order purchased → approved → handed to carrier → delivered. Three violations of this sequence were tested; two occur.

**Scale:**
| Check | Violations | % of applicable rows |
|---|---|---|
| `order_approved_at` < `order_purchase_timestamp` | 0 | — |
| `order_delivered_carrier_date` < `order_approved_at` | 1,359 | 1.39% |
| `order_delivered_customer_date` < `order_delivered_carrier_date` | 23 | 0.02% |
| `order_delivered_customer_date` < `order_purchase_timestamp` | 0 | — |

Separately, 8 orders have status `delivered` but a null `order_delivered_customer_date`, and 2 have status `delivered` with a null `order_delivered_carrier_date`. These do not fit the lifecycle pattern documented in the expected-nulls section.

**Likely cause:** The carrier-before-approval cases are most plausibly a timing artifact — goods dispatched before payment approval cleared, or timestamps written by separate systems without synchronised clocks. The 8 delivered-with-no-date cases appear to be genuine record errors.

**Impact:** Affects dashboard question 3. Any delivery-duration calculation using these rows produces a negative or null interval.

**Decision:** Exclude rows with negative intervals from delivery-time calculations, but **retain them for revenue analysis**, since the monetary values are unaffected and valid. Exclude the 8 delivered-with-null-date orders from delivery-time analysis only. Total exclusion from delivery metrics: 1,390 orders (1.40%).

---

### 8. Usable date range is narrower than the raw range

**What:** The raw range of `order_purchase_timestamp` runs 2016-09-04 to 2018-10-17, which suggests roughly 25 months of data. Monthly volumes show this is misleading at both ends.

**Scale:**
| Period | Orders | Note |
|---|---|---|
| 2016-09 | 4 | Negligible |
| 2016-10 | 324 | Partial |
| 2016-11 | **0** | No orders at all |
| 2016-12 | 1 | Negligible |
| 2017-01 → 2018-08 | 800 → 6,512 | Complete months, growing |
| 2018-09 | 16 | Negligible |
| 2018-10 | 4 | Negligible |

**Likely cause:** The 2016 records appear to be a pilot or test period preceding full platform launch. The November 2016 gap is unexplained but consistent with a pre-launch pause. The 2018-09/10 tail reflects the dataset's extraction cutoff, not a collapse in trading.

**Impact:** Affects every time-series chart. Plotting the raw range produces a near-flat line for four months, a gap, then a spike — and an apparent 99.8% revenue collapse at the end. Both are artifacts.

**Decision:** Restrict all time-series analysis to **2017-01-01 through 2018-08-31** (20 complete months). State this range explicitly on the dashboard. Retain full data for non-time-series aggregates, where the excluded rows are immaterial (329 orders, 0.33%).

---

### 9. Orders with no line items

**What:** 775 orders (0.78%) have no matching rows in `order_items`, meaning they carry no products and no revenue.

**Scale and breakdown by status:**
| Status | Orders |
|---|---|
| unavailable | 603 |
| canceled | 164 |
| created | 5 |
| invoiced | 2 |
| shipped | 1 |

**Likely cause:** 767 of 775 (99.0%) are `unavailable` or `canceled` — orders that never completed, so no line items were ever written. This is expected behaviour, not corruption. The 3 remaining (`invoiced`, `shipped`) are anomalous.

**Impact:** These orders will not appear in an order-item-grain fact table. This is correct — they generated no revenue — but it means order counts derived from the fact table will differ from `count(*)` on `orders` by 775.

**Decision:** Accept the difference; it is the correct behaviour for a revenue fact table. Document the expected gap so that a future reconciliation against `orders` is not mistaken for a modelling error.

---

### 10. Ingestion error: rows split on embedded newlines

**What:** The initial load of `order_reviews` produced 104,162 rows against a documented 99,224, with nulls appearing in `review_id` (1), `order_id` (2,236), and `review_score` (4,937) — columns that are system-generated and should never be null.

**Likely cause:** `review_comment_title` and `review_comment_message` contain customer-written free text including line breaks. The CSV parser, running without multiline handling, treated an embedded newline inside a quoted field as a row terminator, splitting single reviews into two malformed rows.

**Impact:** Would have inflated review counts by ~5% and introduced ~4,900 phantom rows with no score.

**Decision:** Reloaded all nine tables with `multiLine = true`, `quote = '"'`, `escape = '"'`. Row counts now match documented figures for all nine tables. Load statements committed to `sql/01_load_raw.sql`. **This finding concerns the ingestion step, not the source data** — the Olist CSV is correctly formed.

---

## Referential integrity

All foreign key relationships were tested in both directions using a left-join / null-check pattern.

| Relationship | Orphans | Result |
|---|---|---|
| `order_items.order_id` → `orders` | 0 | ✓ |
| `order_items.product_id` → `products` | 0 | ✓ |
| `order_items.seller_id` → `sellers` | 0 | ✓ |
| `order_payments.order_id` → `orders` | 0 | ✓ |
| `order_reviews.order_id` → `orders` | 0 | ✓ |
| `orders.customer_id` → `customers` | 0 | ✓ |

**Reverse direction (parents with no children) — expected, not errors:**

| Check | Count | Note |
|---|---|---|
| Orders with no items | 775 | See Finding 9 |
| Orders with no payment | 1 | See below |
| Orders with no review | 768 | Expected — reviewing is optional |

**Single order with no payment record:** `bfbd0f9bdef84302105ad712db648a6c`, status `delivered`. A delivered order with no payment record is anomalous. Immaterial at one row, but noted; it will appear in item-grain revenue while contributing nothing to payment-based totals.

**Category translation coverage:** 2 category names present in `products` have no entry in `category_name_translation` — `pc_gamer` and `portateis_cozinha_e_preparadores_de_alimentos` — affecting 13 product rows. **Decision:** add manual translations ("PC Gamer" and "Portable Kitchen and Food Preparers") in the staging layer rather than allowing these to become null on join.

---

## Categorical value checks

### order_status (orders)

| Status | Count | % |
|---|---|---|
| delivered | 96,478 | 97.02% |
| shipped | 1,107 | 1.11% |
| canceled | 625 | 0.63% |
| unavailable | 609 | 0.61% |
| invoiced | 314 | 0.32% |
| processing | 301 | 0.30% |
| created | 5 | 0.01% |
| approved | 2 | <0.01% |

No unexpected or misspelled values. The revenue-inclusion cutoff is a decision for `metric-definitions.md`.

### payment_type (order_payments)

| Type | Count |
|---|---|
| credit_card | 76,795 |
| boleto | 19,784 |
| voucher | 5,775 |
| debit_card | 1,529 |
| **not_defined** | **3** |

`not_defined` is a placeholder, not a real payment type — it passes an `IS NULL` check but carries no information. All 3 rows have `payment_value` of 0. **Decision:** immaterial at 3 rows; retain but exclude from any payment-method breakdown, labelled explicitly if shown.

### review_score (order_reviews)

| Score | Count | % |
|---|---|---|
| 1 | 11,424 | 11.51% |
| 2 | 3,151 | 3.18% |
| 3 | 8,179 | 8.24% |
| 4 | 19,142 | 19.29% |
| 5 | 57,328 | 57.78% |

Exactly five values, 1–5, no nulls or out-of-range scores. The distribution is strongly bimodal, skewed positive — 77% of reviews are 4 or 5. **Note for analysis:** with a mean around 4.1 and this shape, the mean is a poor summary statistic. Dashboard question 3 should use the proportion of 1–2 star reviews rather than average score.

### Text value consistency

| Column | Distinct | Distinct after lower + trim | Issue |
|---|---|---|---|
| `customer_city` | 4,119 | 4,119 | None — already normalised |
| `seller_city` | 611 | 611 | None |
| `geolocation_city` | 8,011 | 8,010 | 1 casing duplicate (table scoped out anyway) |
| `customer_state` | 27 | — | Correct — 26 states + Federal District |
| `seller_state` | 23 | — | Sellers absent from 4 states |

City names are already lowercase and trimmed in `customers` and `sellers`. No normalisation required.

### Numeric value sanity

| Check | Result |
|---|---|
| `order_items.price` <= 0 | 0 |
| `order_items.price` range | R$0.85 – R$6,735.00 |
| `order_items.freight_value` < 0 | 0 |
| `order_items.freight_value` = 0 | 383 (0.34%) — free shipping, legitimate |
| `order_payments.payment_value` <= 0 | 9 (0.01%) — all exactly 0 |
| `order_payments.payment_value` range | R$0.00 – R$13,664.08 |
| `order_payments.payment_installments` = 0 | 2 |

No negative values anywhere. The 9 zero-value payments and 2 zero-installment records are immaterial and require no handling.

---

## Payment vs. item reconciliation

Both `order_items` and `order_payments` contain monetary values for the same orders. Each was aggregated to order level independently before comparison, avoiding the fan-out described in Finding 2.

| Measure | Value |
|---|---|
| Orders compared | 98,665 |
| Orders where totals differ by > R$0.01 | 380 (0.39%) |
| Orders where totals differ by > R$1.00 | 249 (0.25%) |
| Total from `order_items` (price + freight) | R$15,843,409.78 |
| Total from `order_payments` | R$15,846,280.17 |
| Net difference | R$2,870.39 (0.018%) |

**Interpretation:** The two sources agree to within 0.02% in aggregate, and 99.6% of orders reconcile exactly. The residual is most likely rounding on installment plans and partial voucher redemptions.

**Decision:** Use **`order_items`** as the revenue source of truth. It sits at the grain the fact table requires, and it attributes revenue to specific products and sellers — which `order_payments` cannot do. `order_payments` is used only for payment-method analysis.

---

## Decisions summary

Consolidated list of every handling decision made above, for cross-reference against `metric-definitions.md`.

| # | Decision |
|---|---|
| 1 | Fact table grain is order-item; compound key `order_id` + `order_item_id` |
| 2 | Never join `order_items` to `order_payments` directly; aggregate each to order level first |
| 3 | Deduplicate reviews to one per order, most recent by `review_creation_date` |
| 4 | `dim_customer` built on `customer_unique_id`; customer counts use it, not `customer_id` |
| 5 | `geolocation` scoped out of the model; city/state sourced from `customers` and `sellers` |
| 6 | Null product categories mapped to `unknown` via `coalesce()`, not dropped |
| 7 | 1,390 orders excluded from delivery-time metrics only; retained for revenue |
| 8 | Time series restricted to 2017-01-01 – 2018-08-31 (20 complete months) |
| 9 | 775 item-less orders will not appear in the fact table; expected, documented |
| 10 | All tables loaded with `multiLine = true`; statements in `sql/01_load_raw.sql` |
| 11 | Two missing category translations added manually in the staging layer |
| 12 | Revenue source of truth is `order_items`, not `order_payments` |
| 13 | Review analysis uses proportion of 1–2 star reviews, not mean score |
