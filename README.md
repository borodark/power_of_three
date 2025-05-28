# Power of Three

## What is Cube[.dev]

Solution for data analitics:
 - documentatin: https://cube.dev/product/cube-core
 - Helm Charts https://github.com/gadsme/charts

How to use cube:
 - Define cubes as collections of measures aggregated along dimensions: DSL, yaml or JS.
 - Decide how to refresh cube data
 - Profit!



## What is Power of Three

Power of Three is the Elixir library that provides macros to define a Cube, Dimensions and Measures along side with our an Ecto.Schema.

_Why inline in Ecto Schema modules?_

  - The names of tables and columns used in defenitions are verified to be present in Ecto.Schema at compile time.
  - I don't like to leave my emacs.

The rest of options are passed as is. The cubes configurations produced at `mix compile`. The cubes configuration files must be shared with cube deployment. DEV environment for crafting Cubes is great: [compose.yaml](./compose.yml)

## Deployment Overview

Four types of containers:
  - API
  - Refresh Workers
  - Cubestore Router
  - Cubestore Workers

Two need the DB connection: API and Refresh Workers
Router needs shared storage with Store Workers. The S3 is fine

## Installation

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
