# PR: Add CubeSchema - Generate Ecto schemas for querying Cube cubes

## Summary

This PR adds `PowerOfThree.CubeSchema`, a new macro that generates Ecto schemas for querying Cube cubes via the PostgreSQL wire protocol. This completes the bidirectional flow between Ecto and Cube.

## Motivation

Power of Three originally provided one direction:
- **Ecto Schema → Cube Config**: Generate Cube YAML configurations from existing Ecto schemas

This PR adds the reverse direction:
- **Cube Config → Ecto Schema**: Generate Ecto schemas that can query existing Cube cubes

This enables Elixir developers to query Cube using familiar Ecto patterns without learning a new query API.

## Dependency

This feature requires [cube-js/cube#10308](https://github.com/cube-js/cube/pull/10308) which fixes Postgrex/Ecto type bootstrap in Cube SQL API.

## New Module: `PowerOfThree.CubeSchema`

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

## Type Mapping

| Cube Type | Ecto Type | Notes |
|-----------|-----------|-------|
| `string` | `:string` | |
| `number` | `:float` | Cube uses floats for most numerics |
| `time` | `:utc_datetime` | |
| `boolean` | `:boolean` | |
| `count` measure | `:integer` | |
| `count_distinct` | `:integer` | |
| `sum`/`avg`/`min`/`max` | `:float` | |

## Supported Ecto Operations

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

## Known Limitations

### Query Syntax Constraints

| Pattern | Issue | Workaround |
|---------|-------|------------|
| `where: x in ^list` | Parameterized IN arrays not supported | Use OR conditions: `where: x == "a" or x == "b"` |
| `where: x not in ^list` | Same as above | Use AND with !=: `where: x != "a" and x != "b"` |
| `fragment(...)` | SQL fragments not supported | Compute in Elixir post-query |
| `having: count() > ^param` | HAVING with params limited | Filter results in Elixir |

### Measure Aggregation Rules

- **Measures in GROUP BY context must be aggregated**: Use `sum(o.count)` not just `o.count`
- **count_distinct measures**: Cannot use `SUM()` on them - use only with count-compatible aggregations
- Parameterized float values may fail (use literal values or string params)
- Scientific notation casts (`1.0e3::float`) are not supported by Cube SQL

### Example Patterns

```elixir
# ❌ Won't work - IN with parameter
from(o in Orders, where: o.brand_code in ^brands)

# ✅ Works - OR conditions
from(o in Orders, where: o.brand_code == "Heineken" or o.brand_code == "Corona Extra")

# ❌ Won't work - raw measure in GROUP BY select
from(o in Orders, group_by: o.brand_code, select: {o.brand_code, o.count})

# ✅ Works - aggregated measure
from(o in Orders, group_by: o.brand_code, select: {o.brand_code, sum(o.count)})
```

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

## Files Changed

- `lib/power_of_three/cube_schema.ex` (new) - The CubeSchema macro module
- `test/cube_schema_live_test.exs` (new) - Live integration tests
- `test/cube_schema_extended_live_test.exs` (new) - Extended live tests
- `mix.exs` - Added `postgrex` dependency for live tests

## Testing

**45 live integration tests** against Cube SQL API on port 9432:

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

Requires Cube SQL API running on localhost:9432.
