# Power of Three

## What is Power of Three

Power of Three is the Elixir library that provides macros to define a [cube](https://cube.dev/docs/product/data-modeling/reference/cube), [dimensions](https://cube.dev/docs/product/data-modeling/reference/dimensions) and [measures](https://cube.dev/docs/product/data-modeling/reference/measures) along side with [Ecto.Schema](https://hexdocs.pm/ecto/Ecto.Schema.html).

This defenitions are complied to cubes config files on `mix compile`.

The yaml output only for now.

The cubes config files then can be be shared with the running _Cube_.

Please see separate project for examples showing working features.
  - [Example 1](https://github.com/borodark/power-of-three-examples/blob/58be8a2d9beb5539d76c42b8e98f51d960fb499c/lib/pot_examples/customer.ex#L26) 
  - [Example 2](https://github.com/borodark/power-of-three-examples/blob/58be8a2d9beb5539d76c42b8e98f51d960fb499c/lib/pot_examples/order.ex#L67)


## What is Cube[.dev]

Solution for data analytics:
 - documentation: https://cube.dev/product/cube-core
 - Helm Charts https://github.com/gadsme/charts

How to use cube:
 - Define cubes as collections of measures aggregated along dimensions: DSL, yaml or JS.
 - Decide how to refresh cube data
 - Profit!


## TODO:

The future plans are bellow in the order of priority:

  - [X] hex.pm documentation
  - [ ] ~~because the `cube` can impersonate `postgres` generate an `Ecto.Schema` Module for the Cubes defined (_full loop_): columns are measures and dimensions connecting to the separate Repo where Cube is deployed.~~ 

    This is *Dropped* for now! The `Ecto` is very particular on what kind of catalog introspections supported by the implementation of `Postgres`. Shall we say: _Cube is not Postgres_ and never will be.

  - [ ] Integrate [Explorer.DataFrame](https://cigrainger.com/introducing-explorer/) having generated Cubes mearures and dimensions as columns, connecting over ADBC to a separate Repo where Cube is deployed.

    Original hope was on `Cube Postgres API` but started [The jorney into the Forests of Traits and the Swamps of Virtual Destructors](https://github.com/borodark/power_of_three/wiki/The-Arrow-Apostasy).

    Looks like we have solid α! The tests show that [data are coming all the way from Cube to DataFrame](https://github.com/borodark/power-of-three-examples/blob/f86cbcfbc15e8ac95a688dfde40b3fcca03d3a7d/test/adbc_cube_basic_test.exs#L174):

      """iex

        {:ok,
        #Explorer.DataFrame<
        Polars[12 x 5]
        FUL string ["partially_returned", "partially_canceled",
        "partially_fulfilled", "returned", "on_hold", ...]
        measure(orders.count) s64 [158, 162, 201, 181, 167, ...]
        measure(orders.subtotal_amount) f64 [2252.3860759493673, 2209.901234567901,
        2107.353233830846, 2174.839779005525, 2057.8383233532936, ...]
        measure(orders.total_amount) f64 [425844.0, 442070.0, 571002.0, 459158.0,
        481116.0, ...]
        measure(orders.tax_amount) f64 [44416.0, 50440.0, 62353.0, 52903.0, 49850.0,
        ...]
        >}
        .
        Finished in 1.2 seconds (1.2s async, 0.00s sync)

    """

  - [ ] support @schema_prefix
  - [ ] validate on pathtrough all options for the cube, dimensions, measures and pre-aggregations
  - [ ] handle `sql_table` names colisions with keywords
  - [ ] validate use of already defined [cube members](https://cube.dev/docs/product/data-modeling/concepts/calculated-members#members-of-the-same-cube) in definitions of other measures and dimensions
  - [ ] handle dimension's `case`
  - [ ] CI integration: what to do with generated yams: commit to tree? push to S3? when in CI?
  - [ ] CI integration: validate yams by starting a cube and make sure configs are sound.
  - [ ] generate default dimensions, measures for all columns of the table if `cube()` macro is used without anything else declared to mimic the capability of cube dev environment

### NOT TODO

Handle of cube's `sql` will not be done. Only `sql_table`.
If you find yourself thinking adding support for `sql`, please fork and let the force be with you.


## _Why inline in Ecto Schema modules?_

The names of tables and columns used in definitions of measures and dimensions are verifiable to be present in Ecto.Schema, hence why write/maintain another yaml or even worse json?


## DEV environment

For crafting Cubes here is the docker: [compose.yaml](https://github.com/borodark/power-of-three-examples/blob/main/compose.yml)


## Deployment Overview

Four types of containers:
  - API
  - Refresh Workers
  - Cubestore Router
  - Cubestore Workers

[![Logical deployment](https://ucarecdn.com/b4695d0a-46a9-4552-93f8-71309de51a43/)](https://cube.dev/docs/product/deployment)

Two need the DB connection: API and Refresh Workers.

Router needs shared storage with Store Workers: S3 is recommended.


## Installation

To install the Cube Core and run locally see here:

- https://cube.dev/docs/product/getting-started
- https://cube.dev/docs/product/deployment/core

To use library

[Available in Hex](https://hexdocs.pm/power_of_3/PowerOfThree.html), the package can be installed
by adding `power_of_3` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:power_of_3, "~> 0.1.2"}
  ]
end
```


