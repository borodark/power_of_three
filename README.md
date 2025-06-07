# Power of Three

## What is Power of Three

Power of Three is the Elixir library that provides macros to define a [cube](https://cube.dev/docs/product/data-modeling/reference/cube), [dimensions](https://cube.dev/docs/product/data-modeling/reference/dimensions) and [measures](https://cube.dev/docs/product/data-modeling/reference/measures) along side with [Ecto.Schema](https://hexdocs.pm/ecto/Ecto.Schema.html).
This defenitions are complied to cubes config files on `mix compile`. The yaml output only for now.
The cubes config files then can be be shared with the running _Cube_.

The [Examples](./lib/example/customer.ex#L27) shows working features. The future plans are bellow in the order of priority:

## What is Cube[.dev]

Solution for data analytics:
 - documentation: https://cube.dev/product/cube-core
 - Helm Charts https://github.com/gadsme/charts

How to use cube:
 - Define cubes as collections of measures aggregated along dimensions: DSL, yaml or JS.
 - Decide how to refresh cube data
 - Profit!

## TODO:
  - [ ] hex.pm worth documentation
  - [ ] validate on pathtrough all options for the cube, dimensions, measures and pre-aggregations
  - [ ] handle cube's `sql` as well as `sql_table`, enforce either
  - [ ] validate use of already defined [cube members:](https://cube.dev/docs/product/data-modeling/concepts/calculated-members#members-of-the-same-cube) in definitions of other measures and dimensions
  - [ ] because the `cube` can impersonate `postgres` implement [Table.Reader](https://hexdocs.pm/table/Table.Reader.html) for [Explorer.DataFrame](https://cigrainger.com/introducing-explorer/) 
  - [ ] handle dimension's `case`
  - [ ] CI integration: what to do with generated yams: commit to tree? push to S3? when in CI?
  - [ ] CI integration: validate yams by starting a cube and make sure configs are sound.
  - [ ] generate default dimensions, measures for all columns of the table if `cube()` macro is used without anything else declared to mimic the capability of cube dev environment
  - [ ] cause the `cube` can impersonate `postgres`: generate an Ecto.Schema for the Cube defined (AKA __full loop_): columns are measures and dimensions

## _Why inline in Ecto Schema modules?_ 

The names of tables and columns used in definitions of measures and dimensions are verifiable to be present in Ecto.Schema, hence why write/maintain another yaml or even worse json?

## DEV environment

For crafting Cubes here is the docker: [compose.yaml](./compose.yml)

## Deployment Overview

Four types of containers:
  - API
  - Refresh Workers
  - Cubestore Router
  - Cubestore Workers

[![Logical deployment](https://ucarecdn.com/b4695d0a-46a9-4552-93f8-71309de51a43/)](https://cube.dev/docs/product/deployment)

Two need the DB connection: API and Refresh Workers
Router needs shared storage with Store Workers: S3 is recommended.

## Installation

To install the Cube Core and run locally see here:
  - https://cube.dev/docs/product/getting-started
  - https://cube.dev/docs/product/deployment/core

To use library

TODO HEX
If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `power_of_3` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:power_of_3, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/power_of_3>.


