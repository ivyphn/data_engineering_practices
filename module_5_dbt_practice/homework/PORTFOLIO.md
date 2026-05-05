# dbt Data Warehouse — Olist Brazilian E-Commerce

> **Stack:** dbt · AWS Athena (Presto SQL) · Amazon S3  
> **Dataset:** [Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — 100k+ real orders, 2016–2018

---

## Table of Contents

1. [What I Built](#1-what-i-built)
2. [Dataset Overview](#2-dataset-overview)
3. [Architecture](#3-architecture)
4. [Project Setup](#4-project-setup)
5. [Step 1 — Seeds](#5-step-1--seeds)
6. [Step 2 — Macros](#6-step-2--macros)
7. [Step 3 — Staging Layer](#7-step-3--staging-layer)
8. [Step 4 — Intermediate Layer](#8-step-4--intermediate-layer)
9. [Step 5 — Marts Layer](#9-step-5--marts-layer)
10. [Step 6 — Testing](#10-step-6--testing)
11. [DAG: Full Model Lineage](#11-dag-full-model-lineage)
12. [How to Run](#12-how-to-run)

---

## 1. What I Built

Raw Olist data arrives as separate CSV tables — orders, customers, products, payments, reviews, and sellers. Without transformation, answering even basic business questions requires messy ad-hoc SQL. The goal here was to build a clean, layered warehouse that analysts can query directly.

**What analysts can answer after this project:**

| Question | Model |
|---|---|
| Revenue and review score per order? | `fct_orders` |
| Which products sold most by region? | `fct_order_items` + `dim_products` + `dim_sellers` |
| Seller on-time delivery rate over time? | `fct_seller_monthly_metrics` |
| What % of the March 2017 cohort is still buying in June? | `fct_customer_cohorts` |
| Who are Champion customers vs Lost customers? | `dim_customer_segments` |

---

## 2. Dataset Overview

Olist is a Brazilian marketplace where sellers list products and ship directly to customers across Brazil.

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

**One thing to know about the source data:** `customer_id` is order-scoped — the same person gets a new `customer_id` for every order they place. The real unique person identifier is `customer_unique_id`. This comes up throughout the project.

---

## 3. Architecture

Three layers, each with a clear job:

```
┌─────────────────────────────────────────────────────────────────┐
│                         RAW SOURCE DATA                         │
│                    (CSV seeds in Athena / S3)                   │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      STAGING  (views)                           │
│  Rename columns, fix data types, apply timezone conversion      │
│  One model per source table. No logic — just cleaning.          │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                   INTERMEDIATE  (views)                         │
│  Aggregate, enrich, and join staging models                     │
│  All business logic lives here — delivery status, RFM, etc.    │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                      MARTS  (tables)                            │
│  dim_* and fct_* tables ready for BI tools                      │
│  Persisted as tables so analyst queries are fast                │
└─────────────────────────────────────────────────────────────────┘
```

Staging and intermediate are `view` — they're just logic, not worth storing. Marts are `table` because that's what analysts query.

---

## 4. Project Setup

### Materialization configured by folder

```yaml
# dbt_project.yml
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

Setting this at the folder level means every model inside automatically inherits the right materialization — no need to configure each file individually.

### Package

```yaml
# packages.yml
packages:
  - package: dbt-labs/dbt_utils
    version: 1.3.3
```

Used for utility macros. Pinned to a specific version so the project builds consistently.

---

## 5. Step 1 — Seeds

Seeds are CSV files loaded into the warehouse by dbt. I used them for two small reference tables that don't come from any source system:

| Seed | Used for |
|---|---|
| `brazil_public_holidays` | Flagging business days in `dim_date` |
| `brazil_state_regions` | Mapping states to macro-regions in `dim_customers` and `dim_sellers` |

Rather than hardcoding region mappings as `CASE` statements in SQL, keeping them in a seed file means they're easy to update and can be tested like any other model:

```yaml
# seeds/brazil_state_regions.yml
- name: macro_region
  tests:
    - accepted_values:
        values: [Norte, Nordeste, Centro-Oeste, Sudeste, Sul]
```

---

## 6. Step 2 — Macros

Three macros in `macros/date_utils.sql` to avoid repeating the same SQL across models.

### `convert_timezone(column_name)`

```sql
{{ convert_timezone('order_purchase_timestamp') }}
```

The source data uses Brasília time (UTC-3). Without conversion, day boundaries shift when the data is read in a different timezone. This macro handles the conversion consistently across all staging models — if the timezone ever needs to change, it's one line.

### `datediff_days(start_col, end_col)`

```sql
{{ datediff_days('order_purchase_timestamp', 'order_delivered_customer_date') }}
```

Presto's `date_diff` silently returns wrong results when either input is NULL. The macro wraps it in a `CASE WHEN ... IS NULL THEN NULL` guard so every lead-time calculation is safe by default.

### `date_part(part, column_name)`

Wraps Presto's non-standard `day_of_week()` so date extraction reads the same as other SQL dialects.

---

## 7. Step 3 — Staging Layer

Each staging model maps 1:1 to a source table. The only job here is cleaning — rename, recast, nothing else.

| Model | What was done |
|---|---|
| `stg_orders` | `convert_timezone()` applied to all 5 timestamp columns |
| `stg_customers` | Zip code cast to `VARCHAR` |
| `stg_order_items` | `price` and `freight_value` cast to `DECIMAL(10,2)` |
| `stg_order_payments` | Payment amounts cast to `DECIMAL(10,2)` |
| `stg_order_reviews` | Verbose names shortened: `review_comment_title` → `comment_title` |
| `stg_products` | Source has a typo: `product_name_lenght` — corrected to `product_name_length` here |
| `stg_sellers` | Zip code cast to `VARCHAR` |
| `stg_product_categories` | Renamed to `category_name_pt` / `category_name_en` to be explicit |
| `stg_public_holidays` | `holiday_date` string cast to `DATE` |

All models use `{{ ref() }}` instead of hardcoded table names — this is how dbt knows the dependency order and builds the DAG.

```sql
-- stg_orders.sql
with source as (
    select * from {{ ref('olist_orders') }}
)
select
    order_id,
    customer_id,
    order_status,
    {{ convert_timezone('order_purchase_timestamp') }}      as order_purchase_timestamp,
    {{ convert_timezone('order_approved_at') }}             as order_approved_at,
    ...
from source
```

---

## 8. Step 4 — Intermediate Layer

This is where raw data becomes business data. Rather than putting all the logic in one big model, I split it by concern:

```
stg_order_items    ────────────────────────────────────────────────┐
stg_order_payments ───► int_orders_payments_agg ───────────────────┤
stg_order_reviews  ───► int_orders_reviews_agg  ───────────────────┼──► int_orders_complete
stg_orders         ───► int_orders_items_agg    ───────────────────┘
```

Each `_agg` model aggregates one thing to order grain. Splitting them up means each one is independently testable and easy to debug.

### `int_orders_payments_agg` — picking the primary payment type

An order can have multiple payment rows (e.g. voucher + credit card split). To get one primary payment type per order, I used `ROW_NUMBER()` ordered by `payment_value desc` — the method with the highest value wins:

```sql
row_number() over (
    partition by order_id
    order by payment_value desc, payment_sequential asc
) as rn
```

### `int_orders_complete` — delivery classification

Delivery status is computed once here and reused in both `fct_orders` and `fct_seller_monthly_metrics`:

```sql
case
    when order_status = 'canceled'                                          then 'cancelled'
    when order_status = 'delivered'
         and order_delivered_customer_date <= order_estimated_delivery_date then 'on_time'
    when order_status = 'delivered'
         and order_delivered_customer_date > order_estimated_delivery_date  then 'late'
    when order_status in ('shipped', 'invoiced', 'processing', ...)        then 'in_transit'
    else 'unknown'
end as delivery_status
```

### `int_customer_rfm` — RFM scoring

RFM scores each customer 1–5 on three dimensions using `NTILE(5)`:

| Dimension | Score 5 (best) | Score 1 (lowest) |
|---|---|---|
| Recency | Ordered most recently | Ordered least recently |
| Frequency | Most orders | Fewest orders |
| Monetary | Highest spend | Lowest spend |

The recency anchor uses `max(last_order_date)` from the data — not `current_date()`. This keeps scores stable and reproducible regardless of when the model runs.

### `int_customers_orders` — resolving the customer_id problem

This model is where `customer_id` (order-scoped) gets aggregated up to `customer_unique_id` (the real person). From this point on, every downstream model works at the true customer grain.

```sql
select
    c.customer_unique_id,
    count(o.order_id)                as total_orders,
    sum(o.total_payment_value)       as lifetime_value,
    min(o.order_purchase_timestamp)  as first_order_date,
    max(o.order_purchase_timestamp)  as last_order_date
from customers as c
left join orders as o on c.customer_id = o.customer_id
group by c.customer_unique_id
```

---

## 9. Step 5 — Marts Layer

### Dimensional model

```
                    ┌─────────────┐
                    │  dim_date   │
                    └──────┬──────┘
                           │ purchase_date_key
┌──────────────────┐       │
│  dim_customers   │◄──────┤
└──────────────────┘       │         ┌──────────────────┐
┌──────────────────┐       ▼         │  fct_order_items │
│ dim_customer_    │  ┌───────────┐  └────────┬─────────┘
│   segments       │  │fct_orders │           │ product_key
└──────────────────┘  └───────────┘  ┌────────▼─────────┐
                                     │  dim_products     │
                                     └──────────────────┘
                                      ┌────────▼─────────┐
                                      │  dim_sellers      │
                                      └──────────────────┘
```

### Dimension tables

#### `dim_date`

Built from a date spine — not from source data. This ensures every calendar day from 2016-01-01 to 2025-12-31 exists, even days with no orders.

```sql
select cast(calendar_date as date) as calendar_date
from (
    values (sequence(date('2016-01-01'), date('2025-12-31'), interval '1' day))
) as t(dates)
cross join unnest(dates) as t2(calendar_date)
```

Includes `is_weekend`, `is_business_day` (false on weekends and Brazilian public holidays), and `is_public_holiday`. Analysts filter on these flags directly instead of writing date logic themselves.

#### `dim_geography`

27 rows — all Brazilian states mapped to one of 5 macro-regions. Loaded from the `brazil_state_regions` seed. Joined into `dim_customers` and `dim_sellers` to add `customer_macro_region` and `seller_macro_region`.

#### `dim_customer_segments`

Translates RFM scores from `int_customer_rfm` into 9 named segments and 4 value tiers:

| Segment | Profile |
|---|---|
| Champions | High R, F, M — best customers |
| Loyal Customers | Buy regularly, solid scores |
| At Risk | Were good customers, gone quiet |
| Cannot Lose Them | High value, going inactive |
| Lost | Low on all three scores |

| Value Tier | M Score |
|---|---|
| Platinum | 5 |
| Gold | 4 |
| Silver | 3 |
| Bronze | 1–2 |

### Fact tables

#### `fct_orders` — one row per order

Core transaction fact. Connects to `dim_customers` and `dim_date`. Key measures: `gross_order_value`, `total_payment_value`, `avg_review_score`, `actual_delivery_days`, `is_late_delivery`.

#### `fct_order_items` — one row per line item

Connects to `dim_products` and `dim_sellers`. Kept separate from `fct_orders` because they have different grains — joining them before aggregating would double-count revenue on multi-item orders.

#### `fct_seller_monthly_metrics` — one row per (seller, month)

Pre-aggregated seller scorecard. Key measures:
- `gmv` — total item revenue
- `on_time_delivery_rate` — share of delivered orders arriving on or before the estimated date
- `cancellation_rate` — share of orders cancelled
- `avg_review_score`

#### `fct_customer_cohorts` — one row per (acquisition_month, activity_month)

Cohort retention table. Each row answers: "Of the customers who first ordered in month X, how many placed an order in month Y?"

```
Acquisition | Activity  | Months Since | Cohort Size | Active | Retention
Jan 2017    | Jan 2017  | 0            | 2,341       | 2,341  | 100%
Jan 2017    | Feb 2017  | 1            | 2,341       | 156    | 6.7%
Jan 2017    | Mar 2017  | 2            | 2,341       | 89     | 3.8%
```

---

## 10. Step 6 — Testing

dbt tests return rows when they fail — an empty result means the test passes.

### Schema tests (in `.yml` files)

Cover the basics on every model: primary keys are `not_null` + `unique`, categorical columns have `accepted_values`.

```yaml
# fct_orders.yml
- name: delivery_status
  tests:
    - not_null
    - accepted_values:
        values: [on_time, late, cancelled, in_transit, unknown]
```

### Singular tests (custom SQL in `tests/`)

Cover business rules that generic tests can't express:

```
tests/
├── staging/
│   ├── test_payment_value_positive.sql             # payment_value <= 0
│   ├── test_item_price_non_negative.sql            # price or freight < 0
│   └── test_payment_installments_positive.sql      # installments < 1
│
├── intermediate/
│   ├── test_delivery_date_after_purchase.sql       # delivered before ordered
│   ├── test_estimated_delivery_after_purchase.sql  # estimated delivery before ordered
│   ├── test_rfm_scores_valid_range.sql             # scores outside 1–5
│   ├── test_total_payment_non_negative.sql
│   └── test_last_order_not_before_first_order.sql
│
└── marts/
    ├── test_fct_orders_customer_key_fk.sql         # FK: orders → dim_customers
    ├── test_fct_orders_date_key_fk.sql             # FK: orders → dim_date
    ├── test_fct_order_items_product_key_fk.sql     # FK: items → dim_products
    ├── test_fct_order_items_seller_key_fk.sql      # FK: items → dim_sellers
    ├── test_dim_customer_segments_fk.sql           # FK: segments → dim_customers
    ├── test_fct_orders_gross_value_calc.sql        # gross = subtotal + freight
    ├── test_cohort_activity_not_before_acquisition.sql
    ├── test_retention_rate_valid_range.sql         # retention between 0 and 1
    ├── test_seller_rates_valid_range.sql           # delivery/cancel rates between 0 and 1
    ├── test_all_customers_have_segment.sql         # every customer has a segment
    └── test_dim_date_no_gaps.sql                  # no missing days in date spine
```

Testing at each layer means a problem surfaces close to its source — a staging data issue shows up as a staging test failure, not as a wrong number in a dashboard.

---

## 11. DAG: Full Model Lineage

```
Seeds
├── olist_orders ─────────────────────────────────► stg_orders
├── olist_customers ──────────────────────────────► stg_customers
├── olist_order_items ────────────────────────────► stg_order_items
├── olist_order_payments ─────────────────────────► stg_order_payments
├── olist_order_reviews ──────────────────────────► stg_order_reviews
├── olist_products ───────────────────────────────► stg_products
├── olist_sellers ────────────────────────────────► stg_sellers
├── olist_product_category_name_translation ──────► stg_product_categories
├── brazil_public_holidays ───────────────────────► stg_public_holidays
└── brazil_state_regions ─────────────────────────────────────────────────┐
                                                                           │
Intermediate                                                               │
├── stg_products + stg_product_categories ────────► int_products_enriched │
├── stg_orders + stg_order_items ─────────────────► int_orders_items_agg  │
├── stg_order_payments ───────────────────────────► int_orders_payments_agg│
├── stg_order_reviews ────────────────────────────► int_orders_reviews_agg │
├── int_orders_items_agg                                                   │
│   + int_orders_payments_agg                                              │
│   + int_orders_reviews_agg ─────────────────────► int_orders_complete   │
├── stg_customers + int_orders_complete ──────────► int_customers_orders  │
└── int_customers_orders ─────────────────────────► int_customer_rfm      │
                                                                           │
Marts                                                                      │
├── brazil_state_regions ◄──────────────────────────────────────────────── ┘
│   └────────────────────────────────────────────► dim_geography
├── stg_customers + int_customers_orders + dim_geography ──► dim_customers
├── int_products_enriched ───────────────────────► dim_products
├── stg_sellers + dim_geography ─────────────────► dim_sellers
├── stg_public_holidays ─────────────────────────► dim_date
├── int_customer_rfm ────────────────────────────► dim_customer_segments
├── int_orders_complete + stg_customers ─────────► fct_orders
├── stg_order_items ─────────────────────────────► fct_order_items
├── stg_order_items + stg_orders
│   + int_orders_reviews_agg ────────────────────► fct_seller_monthly_metrics
└── stg_customers + int_orders_complete ─────────► fct_customer_cohorts
```

**26 models total** — 9 staging · 7 intermediate · 10 marts

---

## 12. How to Run

```bash
# Install packages
dbt deps

# Load seed CSVs into the warehouse
dbt seed

# Build all models
dbt run

# Run all tests
dbt test

# Build + test in one command
dbt build

# Target a specific layer
dbt run --select staging
dbt run --select intermediate
dbt run --select marts

# Run only singular (custom SQL) tests
dbt test --select test_type:singular

# Generate and open docs with the full DAG
dbt docs generate && dbt docs serve
```
