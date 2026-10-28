# Testing

## Quick runs

- Default (unit + compile-only) tests: `mix test`
- Run everything except live Cube tests: `mix test --exclude live_cube`

Live Cube tests are tagged with `:live_cube` and skipped by default
(`ExUnit.start(exclude: [:live_cube, :live_cube_postgres])`).

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

## Live Cube over the Postgres endpoint (Ecto)

`cube_schema_live_test.exs` and `cube_schema_extended_live_test.exs` query
through Ecto and Postgrex on port 9432. They are tagged `:live_cube_postgres`
and not run by `--include live_cube`: Cube's Postgres endpoint can't yet answer
Postgrex's connection bootstrap.

- `pg_type` returns NULL `typsend` and `typoutput`, which crashes Postgrex.
- A `LEFT JOIN` whose `ON` has no equality keys (Postgrex's
  `LEFT JOIN pg_range ... ON r.rngtypid = t.oid OR ...`) is planned as a cross
  join plus a filter, which behaves as an inner join. The bootstrap and reload
  queries then return only the range types, and Postgrex reports
  `oid(s) ... lack type information`.

Run them against a Cube that has both fixed:

- `mix test --include live_cube_postgres`
