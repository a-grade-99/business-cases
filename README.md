# Where a Brazilian Marketplace Loses Its Customers

**An analysis of delivery performance, freight cost and customer satisfaction across 97,308 orders.**

📊 **[View the interactive dashboard on Tableau Public](https://public.tableau.com/app/profile/andr.grade/viz/WhereaBrazilianMarketplaceLosesCustomers/OlistOverview)**

---

## The question

Olist is a Brazilian marketplace connecting small sellers to large e-commerce platforms. Leadership wanted to know which product categories and regions generate profitable revenue once shipping costs are accounted for, and whether delivery performance is affecting customer satisfaction enough to matter.

## The recommendation

**Delivery time past 21 days is the single largest driver of customer dissatisfaction, and it is concentrated in the regions that are already the most expensive to serve.**

Negative review rates hold steady at 7–9% for deliveries under two weeks, then rise to 25.8% at 22–30 days and **64.9% beyond 30 days**. In total, **R$1.81M of revenue — 13.6% of the business — sits in orders taking longer than 21 days, and 40.0% of those customers leave a 1 or 2 star review.**

The same regions carry both problems. Maranhão spends 26.2% of order value on freight against São Paulo's 13.9%, and delivers late 19.3% of the time against a national average of 8.1%. Freight burden scales almost linearly with distance from the southeastern hub: the relationship is tight enough that it points to structural distribution economics rather than state-specific issues.

**Recommended action:** prioritise regional fulfilment capacity in the northeast over broad delivery-speed initiatives. The northeastern states represent a small share of revenue individually, but they concentrate the cost and the dissatisfaction simultaneously — addressing distribution there resolves both, where a national logistics investment would spend most of its budget in regions that are already performing well.

---

## How I got there

### Delivery time drives satisfaction non-linearly

![Negative review rate by delivery bucket](dashboard/delivery-satisfaction.png)

The relationship is not gradual. Satisfaction is essentially flat up to 14 days — customers appear to accept a two-week wait as normal — and then falls off sharply.

| Delivery time | Orders | Negative review rate |
|---|---|---|
| 0–3 days | 8,565 | 7.0% |
| 4–7 days | 24,923 | 7.7% |
| 8–14 days | 36,126 | 9.1% |
| 15–21 days | 15,201 | 12.2% |
| 22–30 days | 6,777 | **25.8%** |
| 31+ days | 3,968 | **64.9%** |

This matters for prioritisation. Improving a 6-day delivery to 4 days buys almost nothing. Moving a 25-day delivery under 21 days is worth roughly 13 percentage points of negative sentiment. **The threshold, not the average, is where the value is** — which is why this analysis reports median (10 days) and p90 (23 days) rather than the mean of 12.5, and why the delivery-day buckets are the primary chart rather than a scatter plot.

### Freight burden varies twofold across states

![Revenue and freight burden by state](dashboard/regional-cost.png)

Plotted on a log revenue scale, the 27 states form a near-linear downward relationship: the larger the market, the smaller the share of order value consumed by shipping.

| State | Revenue share | Freight % of revenue | Late rate | Median days |
|---|---|---|---|---|
| SP | 38.2% | 13.9% | — | — |
| BA | 3.8% | 19.7% | 13.7% | 16 |
| CE | 1.7% | 21.4% | 15.3% | 18 |
| PE | 1.9% | 22.8% | — | — |
| MA | 0.9% | **26.2%** | **19.3%** | 19 |

Two observations follow. The tightness of the relationship suggests the driver is distribution density and distance rather than anything state-specific, which makes it a structural problem with a structural solution. And **revenue is heavily concentrated — São Paulo alone is 38.2% of the total, and the top three states are 63.3%** — meaning the marketplace enjoys strong efficiency where it is dense and pays for it everywhere else.

### Freight burden differs sharply by category

![Revenue and freight burden by category](dashboard/category-profitability.png)

Among the top twelve categories by revenue, the share of order value lost to freight ranges from 8.4% to 23.7%.

| Category | Revenue | Freight % of revenue |
|---|---|---|
| furniture_decor | R$713,300 | **23.7%** |
| housewares | R$622,505 | **23.2%** |
| garden_tools | R$474,170 | 20.6% |
| bed_bath_table | R$1,033,689 | 19.7% |
| health_beauty | R$1,242,523 | 14.5% |
| watches_gifts | R$1,186,334 | **8.4%** |

The pattern is intuitive — bulky, low-density goods cost more to ship relative to their value — but the size of the spread is not. `watches_gifts` and `furniture_decor` differ by a factor of nearly three, which means revenue rank and contribution rank diverge meaningfully. Two categories generating similar revenue can contribute very differently once shipping is netted out.

---

## What the data couldn't tell me

**There is no cost-of-goods data, so true margin cannot be calculated.** Nothing in this analysis is described as margin or profit. The metric used is `contribution_after_freight` (price minus freight), which isolates the effect of shipping cost but says nothing about what the goods cost to acquire. A category with high contribution after freight could still be unprofitable.

**Correlation, not causation, on delivery and satisfaction.** Late deliveries are strongly associated with negative reviews, but the analysis cannot rule out a common cause — for example, that difficult-to-source items are both slower to ship and more likely to disappoint on arrival.

**Reviews are self-selected in content, if not in coverage.** 99.3% of in-scope orders carry a review, which is unusually complete — cancelled and unavailable orders, which account for most missing reviews in the raw data, fall outside this analysis by definition. But review *scores* still reflect who chose to respond and how strongly they felt. The distribution is heavily bimodal (57.8% five-star, 11.5% one-star), characteristic of response patterns driven by strong sentiment in either direction rather than considered rating across the range.

**The window is 20 months, ending August 2018.** The dataset extends to October 2018 and back to September 2016, but those months contain between 1 and 324 orders each — including November 2016 with zero — and including them produces artifacts rather than signal. Twenty complete months is not enough to separate seasonality from trend with confidence.

**Freight cost is what the customer paid, not what shipping cost the business.** The dataset contains no carrier invoices. Where freight is subsidised or marked up, this analysis cannot detect it.

**No repeat-purchase behaviour beyond the window.** 3.4% of customers ordered more than once in 20 months, but customer lifetime value cannot be estimated from a window this short.

---

## Technical detail

### Architecture

Three-layer model in Databricks, built with Spark SQL:

```
raw       nine source tables, loaded unmodified
  ↓
staging   renamed, retyped, lossless (row counts match raw exactly)
  ↓
marts     star schema, business logic applied
```

The separation exists for debugging: when a dashboard number looks wrong, each layer can be checked in turn, and the layer where it first diverges is where the error is.

### Dimensional model

**Two fact tables at different grains**, which was the most consequential modelling decision in the project:

| Table | Grain | Rows | Contains |
|---|---|---|---|
| `fct_order_items` | one row per item | 111,054 | revenue, freight, contribution |
| `fct_orders` | one row per order | 97,308 | delivery days, lateness, review score |

Revenue is an item-level measure; delivery time is an order-level one. An order containing four items has one delivery time, not four. Holding delivery metrics at item grain would weight every average by basket size — a four-item order would count four times toward "average delivery days." Splitting the facts avoids this.

**Dimensions:** `dim_date` (852 rows), `dim_customer` (99,441), `dim_product` (32,951), `dim_seller` (3,095).

There is no `dim_geography`. The source geolocation table has no unique key — 1,000,163 rows across 19,015 postcode prefixes, with 45% of prefixes mapping to more than one city and 42 rows falling outside Brazil's geographic bounds. Joining it unaggregated would have multiplied fact rows roughly 52×. City and state are taken directly from `customers` and `sellers`, both of which are complete.

### Scope

| Parameter | Value |
|---|---|
| Period | 2017-01-01 to 2018-08-31, by purchase date |
| Order status | `delivered`, `shipped` |
| Grain | order-item |
| Orders | 97,308 of 99,441 |
| Revenue | R$13,330,627.12 |

### Validation

`sql/99_validation.sql` runs six checks after any model change. The critical one is revenue reconciliation: total revenue in the fact table must equal total revenue in the filtered source, exactly. This catches join fan-out — where a join to a dimension with duplicate keys silently multiplies rows and inflates every downstream figure. Two further checks confirm that revenue aggregated *through* `dim_product` and `dim_customer` still reconciles, which catches the `unknown` category bucket being dropped.

All six pass. A seventh query reproduces the headline delivery-bucket finding, kept alongside the validation checks so that any future model change that breaks it is noticed immediately.

### Data quality

Full findings in [`docs/data-quality-notes.md`](docs/data-quality-notes.md). The issues that shaped the model:

- **610 products have no category** (1.85% of products, R$179,535 of revenue). Mapped to an explicit `unknown` bucket rather than dropped, so category totals reconcile to headline revenue.
- **`order_reviews` has no unique key.** 547 orders carry multiple reviews; 789 review IDs appear against multiple orders. Deduplicated to the most recent review per order.
- **1,359 orders show carrier handover before payment approval.** Excluded from delivery-time calculations, retained for revenue.
- **Ingestion defect, self-inflicted:** the initial CSV load produced 104,162 review rows against an expected 99,224. Customer review text contains line breaks, and the parser was treating them as row terminators. Corrected by enabling multiline parsing. Documented because the row count not matching the published figure is what surfaced it.

### Metric definitions

Full definitions in [`docs/metric-definitions.md`](docs/metric-definitions.md). Every figure in this README traces to a written definition stating its formula, exclusions, and rationale.

Notable choices:
- **Median and p90 delivery days, never the mean.** The distribution is right-skewed with a tail reaching 209 days.
- **Negative review rate (1–2 stars), not average score.** 57.8% of reviews are 5-star, so the mean has almost no discriminating power: it moves 1.7 points between on-time and late orders, where the negative rate moves nearly sixfold.
- **`order_items` as the revenue source**, not `order_payments`. Both reconcile to within 0.018%, but only `order_items` attributes revenue to specific products and sellers.

### Reproducing this analysis

```
sql/
├── 01_load_raw.sql            nine CSVs → raw tables
├── 02_staging.sql             renamed, retyped views
├── 03_dimensions.sql          four dimension tables
├── 04_facts.sql               two fact tables
├── 05_dashboard_extracts.sql  pre-aggregated CSVs for Tableau
└── 99_validation.sql          six checks + headline finding
```

Run in order. Source CSVs are committed in `data/raw/`.

Dashboards were built on pre-aggregated extracts rather than a live warehouse connection, as Tableau Public Edition ships without database connectors. The extract queries in `05_dashboard_extracts.sql` reproduce directly from the marts layer, and the extracts preserve total revenue exactly.

### Tools

Databricks (Spark SQL) · Tableau Public · Git

### Source

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), Kaggle. Nine tables, ~100k orders, September 2016 – October 2018.
