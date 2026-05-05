# Building a dbt Data Warehouse on Brazilian E-Commerce Data

> **Tech stack:** dbt · AWS Athena (Presto SQL) · Amazon S3  
> **Dataset:** [Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — 100k+ real orders, 2016–2018

---

## Table of Contents

1. [What I Built and Why](#1-what-i-built-and-why)
2. [Dataset Overview](#2-dataset-overview)
3. [Architecture](#3-architecture)
4. [Project Setup](#4-project-setup)
5. [Step 1 — Seeds: Loading Static Reference Data](#5-step-1--seeds-loading-static-reference-data)
6. [Step 2 — Macros: Reusable SQL Utilities](#6-step-2--macros-reusable-sql-utilities)
7. [Step 3 — Staging Layer: Clean Once at the Source](#7-step-3--staging-layer-clean-once-at-the-source)
8. [Step 4 — Intermediate Layer: Business Logic](#8-step-4--intermediate-layer-business-logic)
9. [Step 5 — Marts Layer: Analytics-Ready Tables](#9-step-5--marts-layer-analytics-ready-tables)
10. [Step 6 — Testing Strategy](#10-step-6--testing-strategy)
11. [DAG: Full Model Lineage](#11-dag-full-model-lineage)
12. [Key Design Decisions](#12-key-design-decisions)
13. [How to Run](#13-how-to-run)

---

## 1. What I Built and Why

Raw e-commerce data from Olist arrives as flat CSV exports — orders, customers, products, payments, reviews, and sellers all in separate tables. On its own it is not analyst-friendly: column names are inconsistent, data types are wrong, the customer identifier is order-scoped (not person-scoped), and there is no way for a BI tool to answer questions like *"which seller region has the worst on-time delivery rate?"* without complex ad-hoc SQL.

**The goal:** transform that raw data into a clean, tested, analytics-ready warehouse using dbt best practices — layered models, documented grain, enforced data quality, and reusable logic.

**What an analyst can do after this project:**

| Question | Model |
|---|---|
| What is the revenue and review score per order? | `fct_orders` |
| Which products sold most by region? | `fct_order_items` + `dim_products` + `dim_sellers` |
| How does seller on-time delivery change month over month? | `fct_seller_monthly_metrics` |
| What percentage of the March 2017 cohort is still buying in June? | `fct_customer_cohorts` |
| Who are our Champion customers vs Lost customers? | `dim_customer_segments` |

---

## 2. Dataset Overview

The Olist dataset is a publicly available Brazilian marketplace dataset. One seller can list products on Olist and ship to customers across Brazil.

```
┌─────────────┐     ┌──────────────┐     ┌──────────────────┐
│  Customers  │────▶│    Orders    │────▶│   Order Items    │
└─────────────┘     └──────────────┘     └──────────────────┘
                           │                      │
                    ┌──────┴──────┐        ┌──────┴──────┐
                    │  Payments   │        │   Products  │
                    └─────────────┘        └─────────────┘
                           │                      │
                    ┌──────┴──────┐        ┌──────┴──────┐
                    │   Reviews   │        │   Sellers   │
                    └─────────────┘        └─────────────┘
```

**Key quirk in the source data:** `customer_id` is **order-scoped** — the same physical person gets a new `customer_id` every time they place an order. The true unique customer identifier is `customer_unique_id`. This distinction drives several design decisions throughout the project.

---

## 3. Architecture

This project follows the **three-layer dbt pattern**: Staging → Intermediate → Marts. Each layer has a single, clear responsibility.

```
┌─────────────────────────────────────────────────────────────────┐
│                         RAW SOURCE DATA                         │
│              (CSV seeds loaded into Athena / S3)                │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      STAGING  (views)                           │
│  • One model per source table                                   │
│  • Rename columns, cast data types, apply timezone macro        │
│  • No business logic — just clean the raw data                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                   INTERMEDIATE  (views)                         │
│  • Aggregate, enrich, and join staging models                   │
│  • All business logic lives here (delivery status, RFM, etc.)  │
│  • One concern per model — keep them small and testable         │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      MARTS  (tables)                            │
│  • Dimensions and facts ready for BI tools                      │
│  • Materialized as tables for fast analyst queries              │
│  • Named dim_* and fct_* for instant recognition                │
└─────────────────────────────────────────────────────────────────┘
```

> **Why views for staging and intermediate, but tables for marts?**  
> Staging and intermediate models are transformation logic — they are cheap to recompute and storing them wastes space. Marts are the query layer where analysts run dashboards and ad-hoc queries, so we persist them as tables for performance.

---

## 4. Project Setup

### `dbt_project.yml` — Single source of truth for materializations

```yaml
models:
  homework:
    staging:
      +materialized: view
      +schema: staging
    intermediate:
      +materialized: view
      +schema: intermediate
    marts:
      +materialized: table
      +schema: marts
```

Setting materialization per folder (not per model) means every new model inherits the right behaviour automatically. No need to add `{{ config(materialized=...) }}` to every SQL file.

### `packages.yml` — Third-party utilities

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.3.3
```

`dbt_utils` provides battle-tested macros like `generate_surrogate_key`. Using a versioned package means reproducible builds.

---

## 5. Step 1 — Seeds: Loading Static Reference Data

**Seeds** are CSV files that dbt loads into the warehouse. I used seeds for two static datasets that will never change:

| Seed | Purpose |
|---|---|
| `brazil_public_holidays` | Brazilian national holidays 2016–2025 (used in `dim_date` to flag business days) |
| `brazil_state_regions` | Maps all 27 Brazilian states to one of 5 macro-regions |

> **Best practice:** Use seeds for small, static reference tables that do not come from a source system. Never hardcode these mappings as SQL `CASE` statements — they are hard to maintain and impossible to test.

The seed config in `seeds/brazil_state_regions.yml` also includes data tests:

```yaml
columns:
  - name: macro_region
    tests:
      - accepted_values:
          values: [Norte, Nordeste, Centro-Oeste, Sudeste, Sul]
```

This means even the seed data is tested before it flows into models downstream.

---

## 6. Step 2 — Macros: Reusable SQL Utilities

Rather than writing the same SQL expression in every model, I created macros in `macros/date_utils.sql`.

### `convert_timezone(column_name)`

```sql
-- Usage: {{ convert_timezone('order_purchase_timestamp') }}
-- Output: NULL-safe YYYYMMDD HH:MM:SS string in Australia/Adelaide time
```

**Why this matters:** The Olist dataset uses Brasília time (UTC-3). Analysing timestamps in the wrong timezone produces incorrect day boundaries (e.g. an order at 11 PM Brasília time becomes midnight the next day in UTC+11). By applying timezone conversion in one macro, all staging models stay consistent — if the timezone needs to change, it is a one-line fix.

### `datediff_days(start_col, end_col)`

```sql
-- Usage: {{ datediff_days('order_purchase_timestamp', 'order_delivered_customer_date') }}
-- Output: NULL-safe integer number of days between two timestamps
```

Presto's `date_diff` requires both inputs to be non-null. Wrapping it in a macro with a `CASE WHEN ... IS NULL` guard means we never have to remember to add NULL handling every time we calculate a lead time.

### `date_part(part, column_name)`

Abstracts away Presto's non-standard `day_of_week()` function so models read like plain English.

> **Best practice:** Every time you write the same SQL expression in more than two places, ask whether it belongs in a macro. Macros enforce consistency, reduce bugs, and make the codebase easier to maintain.

---

## 7. Step 3 — Staging Layer: Clean Once at the Source

### Design principles

- **One model per source table** — each model is small, focused, and easy to understand
- **Clean at the boundary** — all type casting happens here, never downstream
- **Rename once** — verbose or misleading column names are fixed here so all downstream models use clean names
- **No business logic** — staging models just rename and recast

### Models built

| Model | Key transformation |
|---|---|
| `stg_orders` | Apply `convert_timezone()` macro to all 5 timestamp columns |
| `stg_customers` | Cast zip code to `VARCHAR`; note the `customer_id` vs `customer_unique_id` distinction |
| `stg_order_items` | Cast `price` and `freight_value` to `DECIMAL(10,2)` |
| `stg_order_payments` | Cast amounts to `DECIMAL(10,2)` |
| `stg_order_reviews` | Shorten verbose column names (`review_comment_title` → `comment_title`) |
| `stg_products` | Fix a **source data typo**: `product_name_lenght` → `product_name_length` |
| `stg_sellers` | Cast zip code to `VARCHAR` |
| `stg_product_categories` | Rename to `category_name_pt` / `category_name_en` — makes intent explicit |
| `stg_public_holidays` | Cast `holiday_date` string to `DATE` |

### Example — `stg_orders.sql`

```sql
with source as (
    select * from {{ ref('olist_orders') }}
)
select
    order_id,
    customer_id,
    order_status,
    {{ convert_timezone('order_purchase_timestamp') }}      as order_purchase_timestamp,
    {{ convert_timezone('order_approved_at') }}             as order_approved_at,
    {{ convert_timezone('order_delivered_carrier_date') }}  as order_delivered_carrier_date,
    ...
from source
```

> **Best practice:** The `with source as (select * from {{ ref(...) }})` pattern is a dbt convention. It makes the source of the model immediately visible at the top of the file, and the `select` below it is the transformation. Clean separation of concerns.

> **Best practice:** Always use `{{ ref() }}` instead of hardcoded table names. This is how dbt builds the dependency graph and ensures models run in the correct order.

---

## 8. Step 4 — Intermediate Layer: Business Logic

The intermediate layer is where raw data becomes business data. Every model here has a single, documented purpose.

### The pattern: aggregate separately, then join

Rather than writing one giant SQL file that aggregates items, payments, and reviews all at once, I split the logic:

```
stg_order_items ─────────────────────────────────────────────────┐
                                                                  │
stg_order_payments ───► int_orders_payments_agg ─────────────────┤
                                                                  ├──► int_orders_complete
stg_order_reviews ────► int_orders_reviews_agg ──────────────────┤
                                                                  │
stg_orders ──────────► int_orders_items_agg ─────────────────────┘
```

**Why?** Each aggregation model (`_agg`) has a single, testable grain. If the payment aggregation has a bug, I can test `int_orders_payments_agg` in isolation without rebuilding everything. When they're all merged into `int_orders_complete`, the join is clean and obvious.

### Key models

#### `int_orders_payments_agg` — Primary payment type detection

```sql
-- Identify the primary payment type as the one with the highest payment value
primary_payment as (
    select order_id, payment_type as primary_payment_type
    from (
        select order_id, payment_type,
            row_number() over (
                partition by order_id
                order by payment_value desc, payment_sequential asc
            ) as rn
        from order_payments
    )
    where rn = 1
)
```

An order can have multiple payment rows (e.g. voucher + credit card). Using `ROW_NUMBER()` with `payment_value desc` ensures we always pick the method with the highest value as the "primary" type — a sensible business rule.

#### `int_orders_complete` — Delivery classification

```sql
case
    when order_status = 'canceled'                      then 'cancelled'
    when order_status = 'delivered'
         and order_delivered_customer_date <= order_estimated_delivery_date
                                                        then 'on_time'
    when order_status = 'delivered'
         and order_delivered_customer_date > order_estimated_delivery_date
                                                        then 'late'
    when order_status in ('shipped','invoiced',...)     then 'in_transit'
    else 'unknown'
end as delivery_status
```

Business logic like this belongs in intermediate, not in the mart. Marts should select and aggregate — they should not contain `CASE` statements that encode business rules.

#### `int_customer_rfm` — RFM Scoring

RFM (Recency, Frequency, Monetary) is a widely-used customer segmentation framework. Each customer gets a score of 1–5 on each dimension using `NTILE(5)`:

| Score | Recency | Frequency | Monetary |
|---|---|---|---|
| 5 (best) | Ordered most recently | Most orders | Highest spend |
| 1 (lowest) | Ordered least recently | Fewest orders | Lowest spend |

```sql
-- R: fewer days since last order = more recent = higher score
ntile(5) over (order by recency_days desc)  as r_score,
-- F: more orders = higher score
ntile(5) over (order by frequency asc)      as f_score,
-- M: higher spend = higher score
ntile(5) over (order by monetary asc)       as m_score
```

The recency anchor is `max(last_order_date)` from the dataset — not `current_date()`. This keeps scores stable and comparable regardless of when the model runs.

#### `int_customers_orders` — Solving the customer_id problem

```sql
-- customer_unique_id can map to multiple customer_id rows
-- Aggregate to true customer grain
select
    c.customer_unique_id,
    count(o.order_id)           as total_orders,
    sum(o.total_payment_value)  as lifetime_value,
    min(o.order_purchase_timestamp) as first_order_date,
    max(o.order_purchase_timestamp) as last_order_date
from customers as c
left join orders as o on c.customer_id = o.customer_id
group by c.customer_unique_id
```

This is where the `customer_id` quirk is resolved. Every downstream model works with `customer_unique_id` as the true person identifier.

---

## 9. Step 5 — Marts Layer: Analytics-Ready Tables

### Dimensional model overview

```
                         ┌──────────────┐
                         │  dim_date    │
                         └──────┬───────┘
                                │ purchase_date_key
┌──────────────────┐            │
│  dim_customers   │◄───────────┤
└──────────────────┘  customer  │
                       _key     │
┌──────────────────┐            │
│ dim_customer_    │            ▼
│   segments       │     ┌──────────────┐     ┌──────────────────┐
└──────────────────┘     │  fct_orders  │     │ fct_order_items  │
                         └──────────────┘     └────────┬─────────┘
                                                       │
                              ┌──────────────┐◄────────┤ product_key
                              │ dim_products │         │
                              └──────────────┘         │ seller_key
                              ┌──────────────┐◄────────┘
                              │  dim_sellers │
                              └──────────────┘
```

### Dimension tables

#### `dim_date` — The most important dimension

`dim_date` is generated from a date spine — no source data required. It covers every calendar day from 2016-01-01 to 2025-12-31 and includes:

- Calendar breakdowns (year, quarter, month, day, day of week)
- `is_weekend` flag
- `is_business_day` flag (false on weekends **and** Brazilian public holidays)
- `is_public_holiday` flag with holiday name and type

```sql
-- Generate one row per calendar day using Presto's sequence() function
select cast(calendar_date as date) as calendar_date
from (
    values (sequence(date('2016-01-01'), date('2025-12-31'), interval '1' day))
) as t(dates)
cross join unnest(dates) as t2(calendar_date)
```

> **Why this matters for analysts:** Instead of writing `WHERE dayofweek(order_date) NOT IN (1,7)` in every query, analysts can join to `dim_date` and filter on `is_business_day = true`. The logic is written once and tested.

#### `dim_geography` — Brazilian macro-regions

27 rows (26 states + Federal District), loaded from the `brazil_state_regions` seed. Used to add `customer_macro_region` and `seller_macro_region` to the customer and seller dimensions.

This makes it trivial for analysts to group by region without knowing Brazilian state codes.

#### `dim_customer_segments` — RFM segmentation

Uses the RFM scores from `int_customer_rfm` to assign each customer to one of 9 segments and one of 4 value tiers:

| RFM Segment | Description |
|---|---|
| Champions | High R, F, and M — buy often, spent a lot, ordered recently |
| Loyal Customers | Buy regularly with good scores across all three dimensions |
| Potential Loyalists | Recent buyers with moderate frequency |
| At Risk | Used to be great customers but haven't bought recently |
| Cannot Lose Them | High value customers going inactive — act now |
| Lost | Low on all three dimensions |

| Value Tier | M Score |
|---|---|
| Platinum | 5 |
| Gold | 4 |
| Silver | 3 |
| Bronze | 1–2 |

### Fact tables

#### `fct_orders` — Core transaction fact

Grain: **one row per order**. Connects to `dim_customers` via `customer_key` and `dim_date` via `purchase_date_key` (integer in `YYYYMMDD` format — fast integer joins).

Key measures: `gross_order_value`, `total_payment_value`, `avg_review_score`, `actual_delivery_days`, `is_late_delivery`.

#### `fct_order_items` — Line-item fact

Grain: **one row per (order_id, order_item_id)**. Connects to `dim_products` and `dim_sellers`. Enables product-level and seller-level revenue analysis.

> **Why two fact tables?** `fct_orders` and `fct_order_items` have different grains. If we merged them, aggregating revenue by order would double-count multi-item orders. Keeping them separate is a fundamental dimensional modelling principle — **never mix grains in one fact table**.

#### `fct_seller_monthly_metrics` — Seller performance scorecard

Grain: **one row per (seller, month)**. Answers questions like "which sellers have a cancellation rate above 10%?" or "how has a seller's average review score trended over time?"

Key measures:
- `gmv` — Gross Merchandise Value (total item revenue)
- `on_time_delivery_rate` — share of delivered orders arriving on or before estimated date
- `cancellation_rate` — share of orders cancelled
- `avg_review_score` — average review score for the month

#### `fct_customer_cohorts` — Cohort retention

Grain: **one row per (acquisition_month, activity_month)**. This table powers cohort retention charts — the most important tool for understanding long-term customer behaviour.

```
Acquisition Month | Activity Month | Months Since | Cohort Size | Active | Retention
Jan 2017          | Jan 2017       | 0            | 2,341       | 2,341  | 100%
Jan 2017          | Feb 2017       | 1            | 2,341       | 156    | 6.7%
Jan 2017          | Mar 2017       | 2            | 2,341       | 89     | 3.8%
```

> `months_since_acquisition = 0` is always `retention_rate = 1.0` (the acquisition month itself). Any month after that shows true retention.

---

## 10. Step 6 — Testing Strategy

Tests in dbt return rows when they fail. An empty result = test passes.

### Two types of tests used

**1. Schema tests** (defined in `.yml` files alongside each model)

These cover universal data quality rules: primary keys are unique and not null, categorical columns only contain expected values.

```yaml
# Example from fct_orders.yml
- name: delivery_status
  tests:
    - not_null
    - accepted_values:
        values: [on_time, late, cancelled, in_transit, unknown]
```

**2. Singular tests** (custom SQL files in `tests/`)

These test business rules that generic tests cannot express. Every test file answers one specific question.

```
tests/
├── staging/
│   ├── test_payment_value_positive.sql          # payment_value <= 0
│   ├── test_item_price_non_negative.sql         # price or freight < 0
│   └── test_payment_installments_positive.sql   # installments < 1
│
├── intermediate/
│   ├── test_delivery_date_after_purchase.sql    # delivered before ordered
│   ├── test_estimated_delivery_after_purchase.sql
│   ├── test_rfm_scores_valid_range.sql          # scores outside 1–5
│   ├── test_total_payment_non_negative.sql
│   └── test_last_order_not_before_first_order.sql
│
└── marts/
    ├── test_fct_orders_customer_key_fk.sql      # FK: orders → dim_customers
    ├── test_fct_orders_date_key_fk.sql          # FK: orders → dim_date
    ├── test_fct_order_items_product_key_fk.sql  # FK: items → dim_products
    ├── test_fct_order_items_seller_key_fk.sql   # FK: items → dim_sellers
    ├── test_dim_customer_segments_fk.sql        # FK: segments → dim_customers
    ├── test_fct_orders_gross_value_calc.sql     # gross = subtotal + freight
    ├── test_cohort_activity_not_before_acquisition.sql
    ├── test_retention_rate_valid_range.sql      # retention between 0 and 1
    ├── test_seller_rates_valid_range.sql        # rates between 0 and 1
    ├── test_all_customers_have_segment.sql      # every customer has a segment
    └── test_dim_date_no_gaps.sql               # no missing days in date spine
```

### Why test at every layer?

```
Raw data ──► Staging tests ──► Intermediate tests ──► Mart tests
              catch type        catch logic bugs       catch FK breaks
              and null issues   early                  and calc errors
```

A bug caught in staging is far cheaper than a bug discovered by an analyst in a dashboard. Testing at every layer means problems surface as close to their source as possible.

---

## 11. DAG: Full Model Lineage

```
Seeds
├── olist_orders ──────────────────────────────► stg_orders
├── olist_customers ───────────────────────────► stg_customers
├── olist_order_items ─────────────────────────► stg_order_items
├── olist_order_payments ──────────────────────► stg_order_payments
├── olist_order_reviews ───────────────────────► stg_order_reviews
├── olist_products ────────────────────────────► stg_products
├── olist_sellers ─────────────────────────────► stg_sellers
├── olist_product_category_name_translation ──► stg_product_categories
├── brazil_public_holidays ────────────────────► stg_public_holidays
└── brazil_state_regions ──────────────────────────────────────────────────┐
                                                                            │
Intermediate                                                                │
├── stg_products + stg_product_categories ─────► int_products_enriched     │
├── stg_orders + stg_order_items ──────────────► int_orders_items_agg       │
├── stg_order_payments ─────────────────────────► int_orders_payments_agg  │
├── stg_order_reviews ──────────────────────────► int_orders_reviews_agg   │
├── int_orders_items_agg                                                    │
│   + int_orders_payments_agg                                               │
│   + int_orders_reviews_agg ──────────────────► int_orders_complete        │
├── stg_customers + int_orders_complete ────────► int_customers_orders      │
└── int_customers_orders ───────────────────────► int_customer_rfm          │
                                                                            │
Marts                                                                       │
├── brazil_state_regions seed ◄──────────────────────────────────────────── ┘
│   └──────────────────────────────────────────► dim_geography
│                                                      │
├── stg_customers + int_customers_orders               │
│   + dim_geography ────────────────────────────► dim_customers
│                                                      │
├── int_products_enriched ──────────────────────► dim_products
│                                                      │
├── stg_sellers + dim_geography ────────────────► dim_sellers
│                                                      │
├── stg_public_holidays ────────────────────────► dim_date
│                                                      │
├── int_customer_rfm ───────────────────────────► dim_customer_segments
│                                                      │
├── int_orders_complete + stg_customers ────────► fct_orders
├── stg_order_items ─────────────────────────────► fct_order_items
├── stg_order_items + stg_orders                        │
│   + int_orders_reviews_agg ───────────────────► fct_seller_monthly_metrics
└── stg_customers + int_orders_complete ────────► fct_customer_cohorts
```

**Total: 9 staging + 7 intermediate + 10 mart = 26 models**

---

## 12. Key Design Decisions

### Decision 1: Separate schema per layer

```
olist.olist_orders   →   staging.stg_orders   →   marts.fct_orders
```

Each layer lives in its own database schema. This means:
- Analysts can be granted read access to `marts` only, keeping intermediate logic hidden
- It is immediately obvious from a table name which layer it belongs to
- Accidental use of staging tables in dashboards is less likely

### Decision 2: One yml file per model

```
❌ Before: _stg_models.yml  (all 9 staging models in one file)
✅ After:  stg_orders.yml, stg_customers.yml, stg_order_items.yml ...
```

With one file per model:
- Git diffs in PRs touch only the changed model's file
- Two people editing different models never have a merge conflict
- Finding a model's documentation is instant — the filename matches the model name

### Decision 3: Resolve the customer_id problem early

The `customer_id` / `customer_unique_id` ambiguity is handled in `int_customers_orders` and never allowed to leak into marts. Every mart model that references customers uses `customer_unique_id` as the key. If this decision had been left to each individual mart author, the warehouse would have inconsistent customer counts across dashboards.

### Decision 4: `dim_date` generated, not sourced

A date dimension built from a spine covers the full date range and is not dependent on whether orders actually exist for a given day. A source-derived date table would be missing dates with no activity, breaking time-series charts.

### Decision 5: Surrogate keys using natural keys

For this dataset, `customer_unique_id`, `product_id`, and `seller_id` are already stable, non-nullable unique identifiers from the source system. Using them as dimension keys directly (rather than generating new surrogate keys) keeps the model simpler without sacrificing correctness.

---

## 13. How to Run

```bash
# Install dependencies
dbt deps

# Load seed data into the warehouse
dbt seed

# Build all models in dependency order
dbt run

# Run all tests
dbt test

# Build and test in one command
dbt build

# Run a specific layer only
dbt run --select staging
dbt run --select intermediate
dbt run --select marts

# Run only singular tests
dbt test --select test_type:singular

# View the full DAG in your browser
dbt docs generate && dbt docs serve
```

---

*Built as part of a Data Engineering practices course covering dbt fundamentals, dimensional modelling, and analytics engineering best practices.*
