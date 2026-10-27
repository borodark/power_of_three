# Testing

## Quick runs

- Default (unit + compile-only) tests: `mix test`
- Run everything except live Cube tests: `mix test --exclude live_cube`

Live Cube tests are tagged with `:live_cube` and skipped by default
(`ExUnit.start(exclude: :live_cube)`).

## Live Cube over HTTP

Requires a running Cube API at `http://localhost:4008`.

- `mix test --include live_cube --include http`

## Live Cube over Arrow Native (port 8120)

Requires cubesqld running with the Arrow Native server on port 8120 (see
`cube/examples/recipes/arrow-ipc`: `start-cube-api.sh`, then
`start-cubesqld.sh`). No driver or extra dependency is needed.

- `mix test --include live_cube --include native`

The pre-aggregation tests (`preagg_routing_test.exs`, `orders_with_preagg`)
also need Cube Store running.
