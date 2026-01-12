defmodule PowerOfThree.CubeSchema do
  @moduledoc """
  Generates Ecto.Schema modules for querying Cube cubes via the PostgreSQL wire protocol.

  This is the reverse of `PowerOfThree` - instead of generating Cube configs from Ecto schemas,
  this generates Ecto schemas that can query existing Cube cubes.

  ## Usage

  ```elixir
  defmodule MyCubes.Orders do
    use PowerOfThree.CubeSchema

    # Generate schema from cube YAML (reads at compile time)
    cube_schema :orders_no_preagg

    # Or with explicit dimensions and measures
    cube_schema :orders_no_preagg do
      dimension :brand_code, :string
      dimension :market_code, :string
      dimension :updated_at, :utc_datetime
      dimension :inserted_at, :utc_datetime

      measure :count, :integer
      measure :total_amount_sum, :float
      measure :tax_amount_sum, :float
    end
  end
  ```

  The generated schema can then be used with a Cube-connected Ecto.Repo:

  ```elixir
  import Ecto.Query

  # Simple query
  Cubes.Repo.all(MyCubes.Orders)

  # With filters
  query = from o in MyCubes.Orders,
    where: o.brand_code == "Heineken",
    limit: 10
  Cubes.Repo.all(query)

  # With aggregation
  query = from o in MyCubes.Orders,
    group_by: o.brand_code,
    select: {o.brand_code, sum(o.total_amount_sum)},
    order_by: [desc: 2],
    limit: 10
  Cubes.Repo.all(query)
  ```

  ## Type Mapping

  Cube types are mapped to Ecto types as follows:

  | Cube Type | Ecto Type | Notes |
  |-----------|-----------|-------|
  | `string` | `:string` | |
  | `number` | `:float` | Cube uses floats for most numerics |
  | `time` | `:utc_datetime` | |
  | `boolean` | `:boolean` | |
  | `count` measure | `:integer` | |
  | `count_distinct` | `:integer` | |
  | `sum` measure | `:float` | |

  ## Primary Key

  Since Cube cubes don't have traditional primary keys, the schema uses a synthetic
  `:id` field of type `:float` (matching Cube's numeric ID handling).

  ## Limitations

  When using Ecto queries with Cube, be aware of these limitations:

  - Parameterized float values may fail (use literal values)
  - Scientific notation casts (`1.0e3::float`) are not supported
  - HAVING clauses with table aliases may not work
  - Filtering on measures requires GROUP BY
  """

  @doc false
  defmacro __using__(_opts) do
    quote do
      import PowerOfThree.CubeSchema, only: [cube_schema: 1, cube_schema: 2]
      Module.register_attribute(__MODULE__, :cube_dimensions, accumulate: true)
      Module.register_attribute(__MODULE__, :cube_measures, accumulate: true)
    end
  end

  @doc """
  Defines an Ecto schema for a Cube cube.

  ## Without block (auto-generate from YAML)

  ```elixir
  cube_schema :orders_no_preagg
  ```

  This reads the cube definition from `model/cubes/<cube_name>.yaml` at compile time.

  ## With block (explicit definition)

  ```elixir
  cube_schema :orders_no_preagg do
    dimension :brand_code, :string
    measure :count, :integer
  end
  ```
  """
  defmacro cube_schema(cube_name) do
    quote do
      cube_name = unquote(cube_name)

      # Try to read from YAML file
      yaml_path = Path.join(["model", "cubes", "#{cube_name}.yaml"])

      case File.read(yaml_path) do
        {:ok, content} ->
          case YamlElixir.read_from_string(content) do
            {:ok, %{"cubes" => [cube | _]}} ->
              # Extract dimensions and measures from YAML
              dimensions = Map.get(cube, "dimensions", [])
              measures = Map.get(cube, "measures", [])

              # Generate fields
              dimension_fields =
                for dim <- dimensions do
                  name = dim["name"] |> to_string() |> String.to_atom()
                  type = PowerOfThree.CubeSchema.cube_type_to_ecto(dim["type"])
                  {name, type}
                end

              measure_fields =
                for m <- measures do
                  name = m["name"] |> to_string() |> String.to_atom()
                  type = PowerOfThree.CubeSchema.measure_type_to_ecto(m["type"])
                  {name, type}
                end

              # Store for schema generation
              Module.put_attribute(__MODULE__, :cube_schema_fields, dimension_fields ++ measure_fields)
              Module.put_attribute(__MODULE__, :cube_schema_name, cube_name)

            _ ->
              raise "Failed to parse cube YAML from #{yaml_path}"
          end

        {:error, _} ->
          raise "Cube YAML not found at #{yaml_path}. Define fields explicitly with cube_schema/2."
      end

      # Generate the Ecto schema
      PowerOfThree.CubeSchema.__generate_schema__(__MODULE__)
    end
  end

  defmacro cube_schema(cube_name, do: block) do
    quote do
      Module.put_attribute(__MODULE__, :cube_schema_name, unquote(cube_name))

      # Import dimension and measure macros for the block
      import PowerOfThree.CubeSchema, only: [dimension: 2, measure: 2]

      # Process the block to collect dimensions and measures
      unquote(block)

      # Generate the Ecto schema
      PowerOfThree.CubeSchema.__generate_schema__(__MODULE__)
    end
  end

  @doc false
  defmacro dimension(name, type) do
    quote do
      Module.put_attribute(__MODULE__, :cube_dimensions, {unquote(name), unquote(type)})
    end
  end

  @doc false
  defmacro measure(name, type) do
    quote do
      Module.put_attribute(__MODULE__, :cube_measures, {unquote(name), unquote(type)})
    end
  end

  @doc false
  def __generate_schema__(module) do
    cube_name = Module.get_attribute(module, :cube_schema_name)

    # Get fields from either YAML parsing or explicit definitions
    fields =
      case Module.get_attribute(module, :cube_schema_fields) do
        nil ->
          dimensions = Module.get_attribute(module, :cube_dimensions) |> Enum.reverse()
          measures = Module.get_attribute(module, :cube_measures) |> Enum.reverse()
          dimensions ++ measures

        fields ->
          fields
      end

    # Check if there's an :id field in dimensions
    has_id = Enum.any?(fields, fn {name, _type} -> name == :id end)

    # Generate the schema AST
    field_asts =
      for {name, type} <- fields do
        quote do
          field(unquote(name), unquote(type))
        end
      end

    schema_ast =
      if has_id do
        quote do
          use Ecto.Schema

          @primary_key {:id, :float, autogenerate: false}

          schema unquote(to_string(cube_name)) do
            unquote_splicing(field_asts)
          end
        end
      else
        quote do
          use Ecto.Schema

          @primary_key false

          schema unquote(to_string(cube_name)) do
            unquote_splicing(field_asts)
          end
        end
      end

    Module.eval_quoted(module, schema_ast)
  end

  @doc """
  Converts Cube dimension type to Ecto type.
  """
  def cube_type_to_ecto(type) when is_binary(type) do
    cube_type_to_ecto(String.to_atom(type))
  end

  def cube_type_to_ecto(:string), do: :string
  def cube_type_to_ecto(:number), do: :float
  def cube_type_to_ecto(:time), do: :utc_datetime
  def cube_type_to_ecto(:boolean), do: :boolean
  def cube_type_to_ecto(_), do: :string

  @doc """
  Converts Cube measure type to Ecto type.
  """
  def measure_type_to_ecto(type) when is_binary(type) do
    measure_type_to_ecto(String.to_atom(type))
  end

  def measure_type_to_ecto(:count), do: :integer
  def measure_type_to_ecto(:count_distinct), do: :integer
  def measure_type_to_ecto(:sum), do: :float
  def measure_type_to_ecto(:avg), do: :float
  def measure_type_to_ecto(:min), do: :float
  def measure_type_to_ecto(:max), do: :float
  def measure_type_to_ecto(:number), do: :float
  def measure_type_to_ecto(_), do: :float
end
