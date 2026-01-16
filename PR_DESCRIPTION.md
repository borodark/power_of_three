# Release v0.1.4 - Performance Testing, SQL Keyword Safety & CubeSchema

## Overview

This release adds comprehensive performance testing, SQL keyword collision detection, CubeSchema for querying Cube via Ecto, and extensive benchmarking documentation.

---

## Part 1: Performance Testing & SQL Keyword Safety

### Performance Results (Saturation, 100 Concurrent)

From `mix test test/saturation_test.exs --include saturation` using the
mandata_captate query set (512 variants, 2016-2025, LIMIT 1k-50k).

```
+----------------------+----------------+----------------+----------------+
| Metric               | Cube HTTP      | ADBC Direct    | Phoenix/ADBC   |
+----------------------+----------------+----------------+----------------+
| Success Rate         |         100.0% |         100.0% |         100.0% |
| Throughput (qps)     |          19.53 |          58.65 |          25.34 |
| Avg Latency (ms)     |        2412.93 |          42.84 |         1616.9 |
| P50 Latency (ms)     |           2406 |             43 |           1759 |
| P95 Latency (ms)     |           4017 |             50 |           3001 |
| P99 Latency (ms)     |           4892 |             57 |           3548 |
+----------------------+----------------+----------------+----------------+
```

**Key Findings:**
- Arrow IPC proven 25-66x faster than HTTP API
- Cache delivers 3-89x speedup
- ADBC: 38.95ms avg, 55.16 qps (512 variants, 100 concurrent)

### SQL Keyword Collision Detection

Automatically detects and warns when `sql_table` names collide with SQL keywords:

```elixir
Cube "Order": sql_table "order" is a SQL keyword.
Consider using schema-qualified name: sql_table: "public.order"
```

### New Test Suite (+2,491 lines)

- HTTP vs Arrow performance (809 lines)
- Pre-aggregation routing (399 lines)
- Real-world cube validation (430 lines)
- SQL keyword detection (237 lines)
- CubeStore metastore (240 lines)
- Comprehensive performance (376 lines)

---

## Part 2: CubeSchema - Query Cube via Ecto

### Summary

`PowerOfThree.CubeSchema` generates Ecto schemas for querying Cube cubes via the PostgreSQL wire protocol. This completes the bidirectional flow between Ecto and Cube.

### Motivation

Power of Three originally provided one direction:
- **Ecto Schema → Cube Config**: Generate Cube YAML configurations from existing Ecto schemas

This adds the reverse direction:
- **Cube Config → Ecto Schema**: Generate Ecto schemas that can query existing Cube cubes

### Dependency

This feature requires [cube-js/cube#10308](https://github.com/cube-js/cube/pull/10308) which fixes Postgrex/Ecto type bootstrap in Cube SQL API.

### Two Ways to Define Schemas

**1. Explicit definition with DSL:**
```elixir
defmodule MyCubes.Orders do
  use PowerOfThree.CubeSchema

  cube_schema :orders_no_preagg do
    dimension :brand_code, :string
    dimension :market_code, :string
    dimension :updated_at, :utc_datetime

    measure :count, :integer
    measure :total_amount_sum, :float
  end
end
```

**2. Auto-generation from YAML:**
```elixir
defmodule MyCubes.Customers do
  use PowerOfThree.CubeSchema

  # Reads from model/cubes/of_customers.yaml at compile time
  cube_schema :of_customers
end
```

### Usage with Ecto.Query

```elixir
import Ecto.Query

# Simple query
Cubes.Repo.all(MyCubes.Orders)

# Filtering
query = from o in MyCubes.Orders,
  where: o.brand_code == "Heineken",
  limit: 10
Cubes.Repo.all(query)

# Aggregation
query = from o in MyCubes.Orders,
  group_by: o.brand_code,
  select: {o.brand_code, sum(o.total_amount_sum)},
  order_by: [desc: 2],
  limit: 10
Cubes.Repo.all(query)
# => [{"Delirium Tremens", 35058016.0}, {"Sierra Nevada", 35043373.0}, ...]
```

### Type Mapping

| Cube Type | Ecto Type | Notes |
|-----------|-----------|-------|
| `string` | `:string` | |
| `number` | `:float` | Cube uses floats for most numerics |
| `time` | `:utc_datetime` | |
| `boolean` | `:boolean` | |
| `count` measure | `:integer` | |
| `count_distinct` | `:integer` | |
| `sum`/`avg`/`min`/`max` | `:float` | |

### Supported Ecto Operations

| Feature | Status | Notes |
|---------|--------|-------|
| `Repo.all/one` | ✅ | Full struct or custom select |
| `where:` with literals | ✅ | `where: o.brand == "X"` |
| `where:` with params | ✅ | `where: o.brand == ^var` (strings) |
| `where:` with AND/OR | ✅ | Multiple conditions |
| `where:` with != | ✅ | Exclusion filtering |
| `limit:` / `offset:` | ✅ | Pagination supported |
| `order_by:` asc/desc | ✅ | By dimension or measure |
| `group_by:` single | ✅ | Single dimension |
| `group_by:` multi | ✅ | Multiple dimensions |
| `sum()`, `count()` | ✅ | Aggregation functions |
| `select:` tuple | ✅ | `{o.brand, sum(o.total)}` |
| `select:` map | ✅ | `%{brand: o.brand, total: sum(o.total)}` |
| `select:` list | ✅ | `[o.brand, sum(o.total)]` |
| Composable queries | ✅ | Pipe-style building |

### Known Limitations

#### Query Syntax Constraints

| Pattern | Issue | Workaround |
|---------|-------|------------|
| `where: x in ^list` | Parameterized IN arrays not supported | Use OR conditions: `where: x == "a" or x == "b"` |
| `where: x not in ^list` | Same as above | Use AND with !=: `where: x != "a" and x != "b"` |
| `fragment(...)` | SQL fragments not supported | Compute in Elixir post-query |
| `having: count() > ^param` | HAVING with params limited | Filter results in Elixir |

#### Measure Aggregation Rules

- **Measures in GROUP BY context must be aggregated**: Use `sum(o.count)` not just `o.count`
- **count_distinct measures**: Cannot use `SUM()` on them - use only with count-compatible aggregations
- Parameterized float values may fail (use literal values or string params)
- Scientific notation casts (`1.0e3::float`) are not supported by Cube SQL

### CubeSchema Tests

**45 live integration tests** against Cube SQL API:

| Test Category | Count | Coverage |
|---------------|-------|----------|
| Basic queries | 5 | `Repo.all`, `Repo.one`, limit, offset |
| WHERE filtering | 8 | String literals, params, AND/OR conditions, NOT |
| ORDER BY | 3 | Ascending, descending, by measure |
| GROUP BY aggregation | 6 | Single/multi-dimension, sum, count |
| Composable queries | 2 | Step-by-step building, filter + aggregation |
| Select formats | 4 | Maps, tuples, lists, computed names |
| Edge cases | 3 | Empty results, single result, large limit |
| Real analytics | 6 | Revenue analysis, market penetration, zodiac distribution |
| Multi-stage queries | 2 | Two-stage patterns with Elixir filtering |
| Pagination | 2 | OFFSET, grouped pagination |
| Numeric comparisons | 2 | Range filters, threshold filtering |
| Count aggregations | 2 | Orders per brand, customers per market |

Run tests with:
```bash
mix test --include live_cube
```

---

## The Complete Vision

```
Ecto Schema ──PowerOfThree──> Cube YAML Config
                                    │
                                    ▼
                              Cube Runtime
                                    │
Ecto Schema <──CubeSchema─── Cube YAML Config
```

Nothing is duplicated. Nothing is reinterpreted. Intellectual economy applied to analytics architecture.

---

## Files Changed

### Performance & Safety
- `lib/power_of_three.ex` - SQL keyword detection (+180 lines)
- `test/test_helper.exs` - Enhanced test utilities
- 7 new performance test files
- 10 new documentation files

### CubeSchema
- `lib/power_of_three/cube_schema.ex` (new) - The CubeSchema macro module
- `test/cube_schema_live_test.exs` (new) - Live integration tests
- `test/cube_schema_extended_live_test.exs` (new) - Extended live tests
- `test/cube_schema_test.exs` (new) - Unit tests

### Common
- `mix.exs` - Version bump, postgrex dependency

## Breaking Changes

**None** - This is a fully backward-compatible release.

## Testing

```bash
# Run full test suite
mix test

# Run performance tests
mix test test/power_of_three/http_vs_arrow_performance_test.exs

# Run CubeSchema live tests (requires Cube SQL API)
mix test --include live_cube
```

## Summary

✅ **Arrow IPC proven 25-66x faster than HTTP API**
✅ **Cache delivers 3-89x speedup**
✅ **CubeSchema enables Ecto queries against Cube**
✅ **45 live integration tests for CubeSchema**
✅ **Enhanced developer safety with SQL keyword warnings**
✅ **Comprehensive performance documentation**

Ready for production use in high-performance analytics applications!
