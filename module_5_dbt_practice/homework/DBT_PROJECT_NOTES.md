# Module 5 – dbt Data Warehouse: Steps & Best Practices

## Project Overview

Built a multi-layer dbt data warehouse on the **Olist Brazilian e-commerce dataset**, following the **staging → intermediate → marts** architecture pattern.

---

## Layer 1: Staging

**What it does:** Clean and rename raw source columns. One model per source table.

**Models built:**
| Model | Grain | Key Notes |
|---|---|---|
| `stg_orders` | one row per `order_id` | timestamps converted via custom macro |
| `stg_customers` | one row per `customer_id` | `customer_id` is order-scoped; `customer_unique_id` is the true person |
| `stg_order_items` | one row per `(order_id, order_item_id)` | price/freight cast to `DECIMAL(10,2)` |
| `stg_order_payments` | one row per payment sequence | multiple rows per order are expected |
| `stg_order_reviews` | one row per `review_id` | verbose column names shortened |
| `stg_products` | one row per `product_id` | dimensions/weight cast to DECIMAL |
| `stg_sellers` | one row per `seller_id` | zip code cast to VARCHAR |
| `stg_product_categories` | one row per category | Portuguese → English translation lookup |
| `stg_public_holidays` | one row per holiday date | Brazilian national holidays 2016–2025 from seed |

**Best practices applied:**
- **Materialized as `view`** — staging models are cheap to recompute and should not store data redundantly.
- **Type casting at the boundary** — monetary values to `DECIMAL(10,2)`, zip codes to `VARCHAR`, scores to `INT`. Never trust raw source types.
- **Rename once** — verbose or unclear column names are shortened here so downstream models always use clean names.
- **Document grain** — every model's `.yml` entry states the expected grain explicitly.
- **Source freshness tests** — sources defined in `_sources.yml` so dbt can validate raw data exists before building.

---

## Layer 2: Intermediate

**What it does:** Pre-aggregate and enrich data to the correct grain for the marts. Business logic lives here.

**Models built:**
| Model | Purpose |
|---|---|
| `int_products_enriched` | Join products with English category names (fallback to Portuguese if missing) |
| `int_orders_items_agg` | Aggregate items to order grain: item count, subtotal, total freight |
| `int_orders_payments_agg` | Aggregate payments to order grain: total value, primary payment type, split flag |
| `int_orders_reviews_agg` | Aggregate reviews to order grain: avg/max score, review count, latest comment |
| `int_orders_complete` | Central order record joining all three aggregates above; computes delivery status |
| `int_customers_orders` | Customer lifetime stats rolled up to `customer_unique_id` grain |
| `int_customer_rfm` | RFM quintile scoring (Recency, Frequency, Monetary) per unique customer |

**Best practices applied:**
- **Materialized as `view`** — intermediate models are transformation logic, not query targets. Views avoid redundant storage.
- **One intermediate model per concern** — items, payments, and reviews are aggregated separately, then joined. This keeps models small and testable.
- **Separate business logic from raw cleaning** — no staging model contains business rules (e.g. delivery status classification); no intermediate model does raw type casting.
- **Grain documented and enforced** — `int_orders_complete` is explicitly one row per `order_id`; the intermediate aggregations guarantee this before the join.
- **Computed flags close to their data** — `is_late_delivery`, `payment_split_flag`, `has_review` are derived here where the source columns are fresh, not recalculated in every downstream mart.

---

## Layer 3: Marts

**What it does:** Produce analytics-ready dimension and fact tables for BI tools and analysts.

**Materialized as `table`** — marts are the query layer. Tables persist results so analyst queries are fast.

### Dimension Tables

| Model | Grain | Key Feature |
|---|---|---|
| `dim_customers` | `customer_unique_id` | Includes lifetime order metrics; Brazilian macro-region mapping |
| `dim_products` | `product_id` | English category name with Portuguese fallback |
| `dim_sellers` | `seller_id` | Macro-region classification |
| `dim_date` | calendar date (2016–2025) | Weekend flag, business day flag, public holiday flag |
| `dim_geography` | Brazilian state (27 rows) | Maps each state to one of 5 macro-regions |
| `dim_customer_segments` | `customer_unique_id` | RFM-based segments (9 types) and value tiers (Platinum/Gold/Silver/Bronze) |

### Fact Tables

| Model | Grain | Key Measures |
|---|---|---|
| `fct_orders` | one row per `order_id` | Revenue, review scores, delivery flags, FK to `dim_customers` + `dim_date` |
| `fct_order_items` | one row per `(order_id, order_item_id)` | Price, freight, FK to `dim_products` + `dim_sellers` |
| `fct_seller_monthly_metrics` | `(seller_key, order_month)` | GMV, on-time delivery rate, cancellation rate, avg review score |
| `fct_customer_cohorts` | `(acquisition_month, activity_month)` | Cohort size, active customers, retention rate, revenue per cohort |

**Best practices applied:**
- **Surrogate keys on dimensions** — `customer_key`, `product_key`, `seller_key` generated with `dbt_utils.generate_surrogate_key` so joins don't depend on source system IDs.
- **Date dimension as a separate model** — `dim_date` is self-contained (no source dependency) and acts as the single source of truth for all calendar logic.
- **Denormalise deliberately** — `dim_customers` includes pre-aggregated lifetime value so simple dashboards don't need to join back to facts.
- **Separation of facts by grain** — `fct_orders` (order grain) and `fct_order_items` (line-item grain) are kept separate. Mixing grains in one fact table causes silent aggregation errors.
- **Semantic naming** — `fct_` prefix for facts, `dim_` prefix for dimensions. Analysts can identify table type at a glance.

---

## Testing Strategy

All primary keys have `not_null` + `unique` tests. Critical foreign keys and categorical columns have `accepted_values` tests.

```yaml
# Example from _stg_models.yml
columns:
  - name: order_id
    tests:
      - not_null
      - unique
  - name: order_status
    tests:
      - accepted_values:
          values: ['delivered', 'shipped', 'canceled', ...]
```

**Best practice:** Test at every layer, not just the mart. A broken staging model caught early saves time debugging downstream.

---

## Materialization Summary

| Layer | Type | Reason |
|---|---|---|
| Staging | `view` | Lightweight cleaning; no need to store |
| Intermediate | `view` | Logic layer; cheap to recompute |
| Marts | `table` | Query target; analysts need fast reads |

---

## Project Conventions

- **Schema-per-layer** — staging → `staging`, intermediate → `intermediate`, marts → `marts`. Keeps raw and transformed data clearly separated in the database.
- **`_sources.yml`** — all raw tables declared as sources, not referenced directly. Enables `dbt source freshness` checks.
- **`_stg_models.yml`, `_int_models.yml`, `_mart_models.yml`** — one config file per layer documenting all models and tests in that layer.
- **Seeds for static data** — public holidays and state region mappings loaded as seeds, not hardcoded in SQL.
- **Custom macro for timestamps** — timezone conversion logic written once in a macro and reused across all staging models that handle timestamps.
