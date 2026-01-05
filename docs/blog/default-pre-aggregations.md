# Default Pre-Aggregations in PowerOfThree

PowerOfThree already auto-generates dimensions and measures for your Ecto schemas. This release adds an opt-in default pre-aggregation so new cubes are fast by construction, without extra DSL work.

## Why This Matters

Pre-aggregations are Cube’s superpower. They turn large scans into fast lookups. The new default pre-aggregation gives you a reasonable rollup right after `mix compile`, and you can still refine it as your needs evolve.

## How to Enable

```elixir
cube :orders, default_pre_aggregation: true
```

### Requirements

- `updated_at` must exist (usually via `timestamps()`).
- The cube must have measures and dimensions.

## What Gets Generated

When enabled and `updated_at` is present, PowerOfThree adds a single rollup:

- `name`: `<sql_table>_automatic_for_the_people`
- `external: true`
- `time_dimension: :updated_at`
- `granularity: :hour`
- `refresh_key`: `SELECT MAX(id) FROM <sql_table>`
- `build_range_start/end`: `NOW() - INTERVAL '1 year'` → `NOW()`
- `dimensions`: all default dimensions except `updated_at` and `inserted_at`

### Example Output (Elixir Snippet)

```elixir
cube :orders,
  sql_table: "public.order",
  default_pre_aggregation: true,
  pre_aggregations: [
    %{
      name: :public_order_automatic_for_the_people,
      type: :rollup,
      external: true,
      measures: [:count, :total_amount_sum],
      dimensions: [:market_code, :brand_code],
      time_dimension: :updated_at,
      granularity: :hour,
      refresh_key: %{sql: "SELECT MAX(id) FROM public.order"},
      build_range_start: %{sql: "SELECT NOW() - INTERVAL '1 year'"},
      build_range_end: %{sql: "SELECT NOW()"}
    }
  ] do
  # dimensions and measures...
end
```

## How to Customize Later

The generated pre-aggregation is just a starting point. You can:

- Drop dimensions that don’t help query patterns.
- Remove heavy measures.
- Change granularity to day/week/month depending on the use case.
- Replace the refresh key with a more accurate watermark.

## Summary

This opt-in default pre-aggregation gives you a fast baseline without extra work. It keeps the scaffolding approach intact: generate, run fast, refine what matters.
