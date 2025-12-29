# PowerOfThree TODO Implementation Plan

```prompt

    Since existing macro construct and populate Module attributes as follows:

       ```elixir
        Module.register_attribute(__MODULE__, :x_cube_primary_keys, accumulate: true)
        Module.register_attribute(__MODULE__, :x_measures, accumulate: true)
        Module.register_attribute(__MODULE__, :x_dimensions, accumulate: true)
        Module.register_attribute(__MODULE__, :x_time_dimensions, accumulate: true)
        Module.register_attribute(__MODULE__, :cube_enabled, persist: true)
        Module.put_attribute(__MODULE__, :cube_enabled, true)
       ```
     it is possible to generate have a Marco that will
      generate for the module `Example.Customer` the following functionality:

     - DOT querieable collection of Measures to be used like example bellow:
       ```elixir
          Example.Customer.measures.aquarii
     ```
   - Dot querieable collection of Dimensions to be used like example bellow:

       ```elixir

            Example.Customer.dimensions.market_code
       ```

     - Explporer Dataframe constructing function:
       ```elixir

            Example.Customer.df(cols: [Example.Customer.dimensions.market_code, Example.Customer.measures.aquarii], opts: [order_by: [], sort_by:[]])

       ```
       - for `sort_by: [Example.Customer.dimensions.market_code,Example.Customer.measures.aquarii]`
         adopt this convension: https://hexdocs.pm/explorer/Explorer.DataFrame.html#sort_by/3

       - same idea for for `order_by: [Example.Customer.dimensions.market_code,Example.Customer.measures.aquarii]`

       - Consider this approach: https://hexdocs.pm/explorer/Explorer.DataFrame.html#filter/2
       to add filter that's specifically to be included to be executed by cube.
```


## Goal

Implement the TODO from `lib/power_of_three.ex:152-191`:
- Dot-accessible measure/dimension collections
- Explorer DataFrame integration via ADBC
- Maintain backwards compatibility with YAML generation

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│ Example.Customer (Ecto Schema + PowerOfThree)        │
├──────────────────────────────────────────────────────┤
│ Generated at compile-time:                           │
│  • Customer.Measures module                          │
│      └─ aquarii() -> %MeasureRef{}                   │
│  • Customer.Dimensions module                        │
│      └─ email() -> %DimensionRef{}                   │
│  • Customer.df(opts) -> %Explorer.DataFrame{} or Map │
└──────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────┐
│ PowerOfThree.QueryBuilder                            │
│  • Builds SQL from MeasureRef/DimensionRef           │
│  • Uses existing CubeQuery.build_cube_sql logic      │
└──────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────┐
│ ADBC Connection Pool (via CubeQuery)                 │
│  • Executes query against Cube (port 8120)           │
│  • Returns Adbc.Result                               │
└──────────────────────────────────────────────────────┘
                         ↓
┌──────────────────────────────────────────────────────┐
│ Optional: Explorer.DataFrame (if available)          │
│  • Wraps result in DataFrame                         │
│  • Applies sorting/filtering                         │
└──────────────────────────────────────────────────────┘
```

---

## Phase 1: Reference Structs & Collections

### 1.1 Create Reference Structs

**File:** `lib/power_of_three/measure_ref.ex`

```elixir
defmodule PowerOfThree.MeasureRef do
  @moduledoc """
  Represents a reference to a cube measure.

  Used in dot-accessible collections like `Customer.measures.aquarii`
  """

  @enforce_keys [:name, :module]
  defstruct [:name, :module, :type, :sql, :meta, :description]

  @type t :: %__MODULE__{
    name: atom() | String.t(),
    module: module(),
    type: atom(),
    sql: term(),
    meta: map(),
    description: String.t() | nil
  }

  @doc "Converts measure reference to SQL column name"
  def to_sql_column(%__MODULE__{module: module, name: name}) do
    cube_name = extract_cube_name(module)
    "MEASURE(#{cube_name}.#{name})"
  end

  defp extract_cube_name(module) do
    # Get cube name from module attributes
    # module.__info__(:attributes)[:cube_config] |> Enum.at(0) |> Map.get(:name)
    # For now, derive from schema source
    module.__schema__(:source)
  end
end
```

**File:** `lib/power_of_three/dimension_ref.ex`

```elixir
defmodule PowerOfThree.DimensionRef do
  @moduledoc """
  Represents a reference to a cube dimension.

  Used in dot-accessible collections like `Customer.dimensions.email`
  """

  @enforce_keys [:name, :module]
  defstruct [:name, :module, :type, :sql, :meta, :description, :primary_key]

  @type t :: %__MODULE__{
    name: atom() | String.t(),
    module: module(),
    type: atom(),
    sql: String.t(),
    meta: map(),
    description: String.t() | nil,
    primary_key: boolean()
  }

  @doc "Converts dimension reference to SQL column name"
  def to_sql_column(%__MODULE__{module: module, name: name}) do
    cube_name = extract_cube_name(module)
    "#{cube_name}.#{name}"
  end

  defp extract_cube_name(module) do
    module.__schema__(:source)
  end
end
```

### 1.2 Generate Accessor Modules

Modify `lib/power_of_three.ex` cube macro postlude (after line 299):

```elixir
# After existing postlude...

# Generate Measures accessor module
measures_functions =
  for measure <- measures do
    measure_name =
      case measure.name do
        name when is_atom(name) -> name
        name when is_binary(name) -> String.to_atom(name)
      end

    quote do
      def unquote(measure_name)() do
        %PowerOfThree.MeasureRef{
          name: unquote(measure.name),
          module: __MODULE__,
          type: unquote(measure.type),
          sql: unquote(Macro.escape(measure[:sql])),
          meta: unquote(Macro.escape(measure[:meta])),
          description: unquote(measure[:description])
        }
      end
    end
  end

Module.create(
  Module.concat(__MODULE__, Measures),
  quote do
    @moduledoc "Accessor module for measures in #{inspect(__MODULE__)}"
    unquote_splicing(measures_functions)
  end,
  Macro.Env.location(__ENV__)
)

# Generate Dimensions accessor module
dimensions_functions =
  for dimension <- dimensions do
    dimension_name =
      case dimension.name do
        name when is_atom(name) -> name
        name when is_binary(name) -> String.to_atom(name)
      end

    quote do
      def unquote(dimension_name)() do
        %PowerOfThree.DimensionRef{
          name: unquote(dimension.name),
          module: __MODULE__,
          type: unquote(dimension.type),
          sql: unquote(dimension.sql),
          meta: unquote(Macro.escape(dimension[:meta])),
          description: unquote(dimension[:description]),
          primary_key: unquote(dimension[:primary_key] || false)
        }
      end
    end
  end

Module.create(
  Module.concat(__MODULE__, Dimensions),
  quote do
    @moduledoc "Accessor module for dimensions in #{inspect(__MODULE__)}"
    unquote_splicing(dimensions_functions)
  end,
  Macro.Env.location(__ENV__)
)

# Generate accessor functions in main module
def measures, do: unquote(Module.concat(__MODULE__, Measures))
def dimensions, do: unquote(Module.concat(__MODULE__, Dimensions))
```

---

## Phase 2: Query Builder

**File:** `lib/power_of_three/query_builder.ex`

```elixir
defmodule PowerOfThree.QueryBuilder do
  @moduledoc """
  Builds SQL queries from MeasureRef and DimensionRef collections.

  Integrates with ExamplesOfPoT.CubeQuery for execution.
  """

  alias PowerOfThree.{MeasureRef, DimensionRef}

  @doc """
  Builds a cube query from column references.

  ## Examples

      columns = [
        Customer.dimensions.brand(),
        Customer.measures.count()
      ]

      QueryBuilder.build_query(
        cube: "customer",
        columns: columns,
        filters: [...],
        order_by: [Customer.dimensions.brand()],
        limit: 10
      )
  """
  def build_query(opts) do
    cube = Keyword.fetch!(opts, :cube)
    columns = Keyword.get(opts, :columns, [])
    filters = Keyword.get(opts, :filters, [])
    order_by = Keyword.get(opts, :order_by, [])
    limit = Keyword.get(opts, :limit)
    offset = Keyword.get(opts, :offset)

    {dimensions, measures} = split_columns(columns)

    # Build SELECT clause
    select_items =
      Enum.map(dimensions, &DimensionRef.to_sql_column/1) ++
      Enum.map(measures, &MeasureRef.to_sql_column/1)

    select_clause = "SELECT #{Enum.join(select_items, ", ")}"

    # Build FROM clause
    from_clause = "FROM #{cube}"

    # Build WHERE clause
    where_clause = build_where_clause(filters)

    # Build GROUP BY clause
    group_by_clause =
      if length(dimensions) > 0 do
        indices = 1..length(dimensions) |> Enum.to_list()
        "GROUP BY #{Enum.join(indices, ", ")}"
      end

    # Build ORDER BY clause
    order_by_clause = build_order_by_clause(order_by)

    # Build LIMIT/OFFSET
    limit_clause = if limit, do: "LIMIT #{limit}"
    offset_clause = if offset, do: "OFFSET #{offset}"

    # Combine
    [
      select_clause,
      from_clause,
      where_clause,
      group_by_clause,
      order_by_clause,
      limit_clause,
      offset_clause
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp split_columns(columns) do
    Enum.split_with(columns, fn
      %DimensionRef{} -> true
      %MeasureRef{} -> false
    end)
  end

  defp build_where_clause([]), do: nil
  defp build_where_clause(filters) when is_list(filters) do
    # TODO: Implement filter DSL
    # For now, accept raw SQL strings
    "WHERE " <> Enum.join(filters, " AND ")
  end

  defp build_order_by_clause([]), do: nil
  defp build_order_by_clause(order_specs) do
    clauses =
      Enum.map(order_specs, fn
        {%DimensionRef{} = dim, direction} ->
          "#{DimensionRef.to_sql_column(dim)} #{direction}"
        {%MeasureRef{} = measure, direction} ->
          "#{MeasureRef.to_sql_column(measure)} #{direction}"
        %DimensionRef{} = dim ->
          DimensionRef.to_sql_column(dim)
        %MeasureRef{} = measure ->
          MeasureRef.to_sql_column(measure)
      end)

    "ORDER BY #{Enum.join(clauses, ", ")}"
  end
end
```

---

## Phase 3: DataFrame Function

Add to cube macro postlude:

```elixir
@doc """
Queries the cube and returns data as Explorer.DataFrame (if available) or map.

## Options

  * `:columns` - List of MeasureRef/DimensionRef (defaults to all)
  * `:filters` - List of filter expressions
  * `:order_by` - List of {ref, :asc/:desc} tuples
  * `:limit` - Row limit
  * `:offset` - Row offset
  * `:pool` - ADBC connection pool module (required)

## Examples

    # Query with specific columns
    df = Customer.df(
      columns: [
        Customer.dimensions.brand(),
        Customer.measures.count()
      ],
      order_by: [{Customer.measures.count(), :desc}],
      limit: 10,
      pool: MyApp.CubePool
    )

    # With Explorer (if available)
    df
    |> Explorer.DataFrame.filter(col("brand") == "Acme")
    |> Explorer.DataFrame.head(5)
"""
def df(opts \\ []) do
  require PowerOfThree.QueryBuilder, as: QB

  pool = Keyword.fetch!(opts, :pool)
  cube_name = unquote(sql_table)

  # Get all available columns if not specified
  columns = Keyword.get_lazy(opts, :columns, fn ->
    all_dimensions() ++ all_measures()
  end)

  # Build SQL query
  sql = QB.build_query(
    cube: cube_name,
    columns: columns,
    filters: Keyword.get(opts, :filters, []),
    order_by: Keyword.get(opts, :order_by, []),
    limit: Keyword.get(opts, :limit),
    offset: Keyword.get(opts, :offset)
  )

  # Execute query via pool
  case pool.query(sql) do
    {:ok, result} ->
      materialized = Adbc.Result.materialize(result)
      data_map = Adbc.Result.to_map(materialized)

      # Try to use Explorer if available
      case Code.ensure_loaded(Explorer.DataFrame) do
        {:module, _} ->
          {:ok, Explorer.DataFrame.new(data_map)}
        {:error, _} ->
          {:ok, data_map}
      end

    {:error, error} ->
      {:error, error}
  end
end

@doc "Same as df/1 but raises on error"
def df!(opts \\ []) do
  case df(opts) do
    {:ok, result} -> result
    {:error, error} -> raise "DataFrame query failed: #{inspect(error)}"
  end
end

# Helper to get all dimension refs
defp all_dimensions do
  unquote(dimensions)
  |> Enum.map(fn dim ->
    name = case dim.name do
      n when is_atom(n) -> n
      n when is_binary(n) -> String.to_atom(n)
    end
    __MODULE__.Dimensions.unquote(name)()
  end)
end

# Helper to get all measure refs
defp all_measures do
  unquote(measures)
  |> Enum.map(fn measure ->
    name = case measure.name do
      n when is_atom(n) -> n
      n when is_binary(n) -> String.to_atom(n)
    end
    __MODULE__.Measures.unquote(name)()
  end)
end
```

---

## Phase 4: Configuration

Add to `lib/power_of_three.ex` module attributes:

```elixir
@doc """
Configures the ADBC connection pool for cube queries.

Must be called before using df/1.

## Options

  * `:pool_module` - Module implementing the connection pool
  * `:host` - Cube server host (default: "localhost")
  * `:port` - Cube ADBC port (default: 8120)
  * `:token` - Authentication token (default: "test")

## Examples

    defmodule Example.Customer do
      use Ecto.Schema
      use PowerOfThree

      # Configure cube pool
      cube_pool MyApp.CubePool,
        host: "localhost",
        port: 8120,
        token: System.get_env("CUBE_TOKEN")

      schema "customer" do
        field(:email, :string)
      end

      cube :of_customers, sql_table: "customer" do
        dimension(:email)
        measure(:count)
      end
    end

    # Now df/1 works without explicit pool:
    Customer.df(columns: [Customer.dimensions.email()])
"""
defmacro cube_pool(pool_module, opts \\ []) do
  quote bind_quoted: [pool_module: pool_module, opts: opts] do
    Module.put_attribute(__MODULE__, :cube_pool_module, pool_module)
    Module.put_attribute(__MODULE__, :cube_pool_opts, opts)
  end
end
```

---

## Phase 5: Optional Explorer Integration

Use compile-time conditional compilation:

```elixir
# In df/1 function
if Code.ensure_loaded?(Explorer.DataFrame) do
  defp to_dataframe(data_map) do
    Explorer.DataFrame.new(data_map)
  end
else
  defp to_dataframe(data_map) do
    data_map
  end
end
```

Add to `mix.exs` in PowerOfThree:

```elixir
def deps do
  [
    {:explorer, "~> 0.8", optional: true},
    # ... existing deps
  ]
end
```

---

## Phase 6: Testing

**File:** `test/power_of_three_dataframe_test.exs`

```elixir
defmodule PowerOfThreeDataFrameTest do
  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :requires_cube_server

  # Start services before tests
  setup_all do
    # Start Cube services
    cube_dir = Path.expand("~/projects/learn_erl/cube/examples/recipes/arrow-ipc")

    # Start Cube API
    cube_api_port = System.cmd("bash", [
      "-c",
      "cd #{cube_dir} && ./start-cube-api.sh > /dev/null 2>&1 & echo $!"
    ])

    :timer.sleep(5000)  # Wait for Cube API

    # Start cubesqld
    cubesqld_port = System.cmd("bash", [
      "-c",
      "cd #{cube_dir} && ./start-cubesqld.sh > /dev/null 2>&1 & echo $!"
    ])

    :timer.sleep(3000)  # Wait for cubesqld

    on_exit(fn ->
      # Cleanup
      System.cmd("kill", [cube_api_port])
      System.cmd("kill", [cubesqld_port])
    end)

    :ok
  end

  defmodule TestCustomer do
    use Ecto.Schema
    use PowerOfThree

    schema "customer" do
      field(:email, :string)
      field(:brand, :string)
    end

    cube :test_customers, sql_table: "customer" do
      dimension(:email)
      dimension(:brand)
      measure(:count)
    end
  end

  test "dot-accessible measures" do
    measure = TestCustomer.measures.count()
    assert %PowerOfThree.MeasureRef{} = measure
    assert measure.name in [:count, "count"]
    assert measure.type == :count
  end

  test "dot-accessible dimensions" do
    dim = TestCustomer.dimensions.email()
    assert %PowerOfThree.DimensionRef{} = dim
    assert dim.name in [:email, "email"]
  end

  test "df/1 with ADBC pool" do
    # Assuming pool is configured
    result = TestCustomer.df(
      columns: [
        TestCustomer.dimensions.brand(),
        TestCustomer.measures.count()
      ],
      pool: ExamplesOfPoT.CubePool,
      limit: 5
    )

    assert {:ok, data} = result
    # data is either DataFrame or Map depending on Explorer availability
  end
end
```

---

## Implementation Checklist

- [x] Phase 1: Reference structs (MeasureRef, DimensionRef)
- [x] Phase 1: Generate Measures/Dimensions accessor modules
- [x] Phase 2: QueryBuilder module
- [x] Phase 3: df/1 and df!/1 functions
- [x] Phase 4: Configuration support
- [x] Phase 5: Optional Explorer integration
- [x] Phase 6: Integration tests

---

## Next Steps

1. **Create reference struct modules** (`measure_ref.ex`, `dimension_ref.ex`)
2. **Modify cube macro** to generate accessor modules
3. **Implement QueryBuilder**
4. **Add df/1 function** to generated modules
5. **Write integration tests** with service lifecycle management
6. **Update documentation** with examples

Would you like me to start implementing any specific phase?
