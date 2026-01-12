# Testing

## Quick runs

- Default (unit + compile-only) tests: `mix test`
- Run everything except live Cube tests: `mix test --exclude live_cube`

Live Cube tests are tagged with `:live_cube` and skipped by default
(`ExUnit.start(exclude: :live_cube)`).

## Live Cube over HTTP

Requires a running Cube API at `http://localhost:4008`.

- `mix test --include live_cube --include http`

## Live Cube over ADBC (adbc_driver_cube)

Requires:
- `adbc` dependency available
- `adbc_driver_cube` binaries available locally or auto-downloaded
- cubesqld running with ADBC enabled

If you want tests to download the driver automatically, set:

- `CUBE_DRIVER_AUTO_DOWNLOAD=1`
- `CUBE_DRIVER_VERSION=0.1.2` (optional)

Run ADBC tests:

- `mix test --include live_cube --include adbc`

If you already have a local driver build, ensure it is discoverable by
`Adbc.Driver.so_path(:cube, version: ...)` or set the matching version.
