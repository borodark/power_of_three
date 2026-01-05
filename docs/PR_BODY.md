# PR: Default Pre-Aggregations (Opt-In)

## Overview
- Adds an opt-in default pre-aggregation for auto-generated cubes when `updated_at` exists.
- Prints the pre-aggregation block in the auto-generated Elixir snippet.
- Enforces a consistent pre-aggregation name suffix: `_automatic_for_the_people`.
- Adds Cube HTTP integration coverage across date granularities/ranges.
- Documents the new flag in README and quick reference.

## What’s New
- `default_pre_aggregation: true` generates a single rollup pre-aggregation.
- Rollup defaults:
  - `external: true`
  - `time_dimension: :updated_at`
  - `granularity: :hour`
  - `refresh_key: SELECT MAX(id) FROM <sql_table>`
  - `build_range_start/end` based on `NOW()`
  - excludes `updated_at` and `inserted_at` from dimensions
- Printed cube snippet now shows the pre-aggregation block (suppressed when `sql_table` is unknown).

## Testing
```bash
mix test test/power_of_three/default_cube_test.exs
mix test test/power_of_three/preagg_default_integration_test.exs --include live_cube
```

## Notes
- Fully backward compatible.
- Pre-aggregation remains editable after generation.
