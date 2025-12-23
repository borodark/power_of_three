defmodule PowerOfThree do
  @moduledoc ~S"""
  The `PowerOfThree` defines three macros to be used with Ecto.Schema to creates cube config files.
  The PowerOfThree must be used after `using Ecto.Schema `.
  The `Ecto.Schema` defines table column names to be used in measure and dimensions defenitions.

  The definition of the Cude is possible through main APIs:
  `cube/3`.

  `cube/3` has to define `sql_table:` that is refering Ecto schema `source`.

  After using `Ecto.Schema` and `PowerOfThree` define cube with `cube/2` macro.

  ## Example

      defmodule Example.Customer do
        use Ecto.Schema
        use PowerOfThree

        schema "customer" do
          field(:first_name, :string)
          field(:last_name, :string)
          field(:email, :string)
          field(:birthday_day, :integer)
          field(:birthday_month, :integer)
          field(:brand_code, :string)
          field(:market_code, :string)
        end

        cube :of_customers,       # name of the cube: mandatory
          sql_table: "customer",  # Ecto.Schema `source`: mandatory
                                  # Only `sql_table:` is supported. Must reference EctoSchema `:source`
                                  # the `sql:` is not supported and never will be.
          description: "of Customers"
                                  # path through options in accordance with Cube DSL

          dimension(
            [:brand_code, :market_code, :email],
                                  # several fields of `customer` Ecto.Schema: mandatory
                                  # the list is validated against list of fields of EctoSchema
            name: :email_per_brand_per_market,
                                  # dimensions `name:`, optional.
            primary_key: true     # This `customer:` table supports only one unique combination of
                                  # `:brand_code`, `:market_code`, `:email`
            )

          dimension(
            :first_name,          # a field of `customer` Ecto.Schema: mandatory
                                  # validated against list of fields of EctoSchema
            name: :given_name,    # dimension `name:` optional
            description: "Given Name"
                                  # path through options in accordance with Dimension DSL
            )

          measure(:count)         # measure of type `count:` is a special one: no column reference in `sql:` is needed
                                  # `name:` defaults to `count:`

          measure(:email,         # measures counts distinct of `email:` column
            name: :aquarii,       # name it proper latin plural
            type: :count_distinct,
            description: "Only count Aquariuses", # add `description:` and `filter:` in options
            filters: [%{sql: "(birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18)"}]
                                  # correct SQL refrencing correct columns
                                  # `filters:` uses an SQL clause to not count others
          )
        end
      end

  After creating a few dimensions and measures run `mix compile`. The following yaml is created for the above:

  ```yaml

  ---
  cubes:
    - name: of_customers
      description: of Customers
      sql_table: customer
      measures:
        - name: count
          type: count
        - meta:
            ecto_field: email
            ecto_type: string
          name: aquarii
          type: count_distinct
          description: Only count Aquariuses
          filters:
            - sql: (birthday_month = 1 AND birthday_day >= 20) OR (birthday_month = 2 AND birthday_day <= 18)
          sql: email
      dimensions:
        - meta:
            ecto_fields:
              - brand_code
              - market_code
              - email
          name: email_per_brand_per_market
          type: string
          primary_key: true
          sql: brand_code||market_code||email
        - meta:
            ecto_field: first_name
            ecto_field_type: string
          name: given_name
          type: string
          description: Given Name
          sql: first_name

  ```

  ## Auto-Generated Default Cube

  When `cube/2` is called without a block, PowerOfThree automatically generates dimensions and measures
  based on your Ecto schema field types. This provides a quick way to get started without manually
  defining each dimension and measure.

  ### Auto-Generation Rules

  **Dimensions** are created for these field types:
  - `:string`, `:binary`, `:binary_id`, `:bitstring` → string dimension
  - `:boolean` → boolean dimension
  - `:date`, `:time`, `:naive_datetime`, `:utc_datetime` (and `_usec` variants) → time dimension

  **Measures** are created as follows:
  - `count` - always generated (counts all rows)
  - For `:integer` and `:id` fields - TWO measures per field:
    - `<field>_sum` - sums the values
    - `<field>_distinct` - counts distinct values
  - For `:float` and `:decimal` fields:
    - `<field>_sum` - sums the values

  ### Example

      defmodule Example.Product do
        use Ecto.Schema
        use PowerOfThree

        schema "products" do
          field :name, :string
          field :description, :string
          field :active, :boolean
          field :price, :float
          field :quantity, :integer
          timestamps()  # adds inserted_at and updated_at
        end

        # Auto-generates all dimensions and measures
        cube :products, sql_table: "products"
      end

  This auto-generates:
  - **Dimensions**: `id`, `name`, `description`, `active`, `inserted_at`, `updated_at`
  - **Measures**: `count`, `id_sum`, `id_distinct`, `quantity_sum`, `quantity_distinct`, `price_sum`

  Accessor functions are created for all auto-generated dimensions and measures:

      Product.Dimensions.name()         # Access name dimension
      Product.Measures.quantity_sum()   # Access quantity sum measure
      Product.Measures.price_sum()      # Access price sum measure

  ### When to Use Auto-Generation vs Explicit Block

  **Use auto-generation** when:
  - You want all fields as dimensions and standard aggregations
  - Prototyping or getting started quickly
  - Your schema has simple field types that map directly to cube concepts

  **Use explicit block** when:
  - You need custom SQL expressions in dimensions
  - You want filtered measures
  - You need multi-field dimensions (concatenated)
  - You want to exclude certain fields
  - You need custom measure names or types

  ## Accessing Dimensions and Measures

  PowerOfThree generates accessor functions for dimensions and measures in two ways:

  ### Module Accessors

  Individual dimensions and measures can be accessed via generated modules:

      Customer.Dimensions.brand()       # Returns %PowerOfThree.DimensionRef{}
      Customer.Dimensions.email()
      Customer.Measures.count()         # Returns %PowerOfThree.MeasureRef{}
      Customer.Measures.aquarii()

  ### List Accessors

  Get all dimensions or measures as lists:

      dimensions = Customer.dimensions()  # Returns [%PowerOfThree.DimensionRef{}, ...]
      measures = Customer.measures()      # Returns [%PowerOfThree.MeasureRef{}, ...]

      # Find specific dimension/measure from list
      brand = Enum.find(dimensions, fn d -> d.name == :brand end)
      count = Enum.find(measures, fn m -> m.name == "count" end)

  ### Building Queries

  Both accessor styles can be used with QueryBuilder and df/1:

      # Using module accessors
      Customer.df(columns: [
        Customer.Dimensions.brand(),
        Customer.Measures.count()
      ])

      # Using list accessors
      dimensions = Customer.dimensions()
      measures = Customer.measures()

      Customer.df(columns: [
        Enum.find(dimensions, fn d -> d.name == :brand end),
        Enum.find(measures, fn m -> m.name == "count" end)
      ])

  ## Type Mapping

  The dimensions and measures derive some defaults from `Ecto.Schema.field` properties.
  For example the `dimension:` `type:` is derived from ecto if not given explicitly according to this rules:

  Cube dimension types    | Ecto type               | Elixir type
  :---------------------- | :---------------------- | :---------------------
  number                  | :id                     | integer
  string                  | :binary_id              | binary
  number, boolean         | :integer                | integer
  number, boolean enough? | :float                  | float
  boolean                 | :boolean                | boolean
  string                  | UTF-8 encoded `string`  | string
  string                  | :binary                 | :binary
  string                  | :bitstring              | :bitstring
  `{:array, inner_type}`  | `list`                  | TODO geo?
  Not Supported now       | `:map`                  | `map`
  Not Supported now       | `{:map, inner_type}`    | `map`
  number                  | `:decimal`              | [`Decimal`](https://github.com/ericmj/decimal)
  time                    | `:date`                 | `Date`
  time                    | `:time`                 | `Time`
  time                    | `:time_usec`            | `Time`
  time                    | `:naive_datetime`       | `NaiveDateTime`
  time                    | `:naive_datetime_usec`  | `NaiveDateTime`
  time                    | `:utc_datetime`         | `DateTime`
  time                    | `:utc_datetime_usec`    | `DateTime`
  number                  | `:duration`             | `Duration`




  The goal of `PowerOfThree` is to cover 80% of cases where the `source` of Ecto Schema is a table and fields have real column names:
   _where *field name =:= database column name*_

  The the support of all cube features is not the goal here.
  The automation of obtaining the usable cube configs with minimal verbocity is: avoid typing more typos then needed.

  The cube DSL allows the `sql:` - _any SQL_ query. If everyone can write SQL it does not mean everyone should.
  Writing good SQL is an art a few knew. In the memory of Patrick's Mother  the `PowerOfThree` will _not_ support `sql:`.
  While defining custom `sql:` may looks like an option, how would one validate the creative use of aliases in SQL?
  Meanwhile Ecto.Schema fields are available for references to define dimensions `type:`.

  """

  defmacro __using__(_) do
    quote do
      import PowerOfThree,
        only: [cube: 2, cube: 3, dimension: 2, measure: 2, time_dimensions: 1]

      require Logger

      Module.register_attribute(__MODULE__, :cube_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :measures, accumulate: true)
      Module.register_attribute(__MODULE__, :dimensions, accumulate: true)
      Module.register_attribute(__MODULE__, :time_dimensions, accumulate: true)
      Module.put_attribute(__MODULE__, :cube_enabled, true)
      #
    end
  end

  # Helper function to generate pretty-printed cube source code for display
  @doc false
  def generate_cube_source_code(cube_name, opts, ecto_fields) do
    alias IO.ANSI

    # Fields to skip (system fields)
    skip_fields = [:id, :inserted_at, :updated_at]

    # Filter out skipped fields
    user_fields =
      Enum.reject(ecto_fields, fn {field, _type} ->
        field in skip_fields
      end)

    # Filter fields by type
    string_fields =
      Enum.filter(user_fields, fn {_field, {type, _}} ->
        type in [:string, :binary, :binary_id, :bitstring, :boolean]
      end)

    time_fields =
      Enum.filter(user_fields, fn {_field, {type, _}} ->
        type in [
          :naive_datetime,
          :naive_datetime_usec,
          :utc_datetime,
          :utc_datetime_usec,
          :date,
          :time,
          :time_usec
        ]
      end)

    integer_fields =
      Enum.filter(user_fields, fn {_field, {type, _}} ->
        type in [:integer, :id]
      end)

    float_fields =
      Enum.filter(user_fields, fn {_field, {type, _}} ->
        type in [:float, :decimal]
      end)

    # Get sql_table from opts
    sql_table = Keyword.get(opts, :sql_table, "unknown")

    # Build the source code string with syntax highlighting
    lines = [
      "",
      "#{ANSI.bright()}#{ANSI.blue()}# Auto-generated cube definition (copy-paste ready):#{ANSI.reset()}",
      "",
      "#{ANSI.yellow()}cube#{ANSI.reset()} #{ANSI.cyan()}:#{cube_name}#{ANSI.reset()},",
      "  #{ANSI.magenta()}sql_table:#{ANSI.reset()} #{ANSI.green()}\"#{sql_table}\"#{ANSI.reset()} #{ANSI.blue()}do#{ANSI.reset()}",
      ""
    ]

    # Add dimensions
    dimension_lines =
      (string_fields ++ time_fields)
      |> Enum.map(fn {field, _} ->
        "  #{ANSI.yellow()}dimension#{ANSI.reset()}(#{ANSI.cyan()}:#{field}#{ANSI.reset()})"
      end)

    lines = lines ++ dimension_lines

    lines = if dimension_lines != [], do: lines ++ [""], else: lines

    # Add measures
    measure_lines = [
      "  #{ANSI.yellow()}measure#{ANSI.reset()}(#{ANSI.cyan()}:count#{ANSI.reset()})"
    ]

    integer_measure_lines =
      integer_fields
      |> Enum.flat_map(fn {field, _} ->
        [
          "  #{ANSI.yellow()}measure#{ANSI.reset()}(#{ANSI.cyan()}:#{field}#{ANSI.reset()}, #{ANSI.magenta()}type:#{ANSI.reset()} #{ANSI.cyan()}:sum#{ANSI.reset()}, #{ANSI.magenta()}name:#{ANSI.reset()} #{ANSI.cyan()}:#{field}_sum#{ANSI.reset()})",
          "  #{ANSI.yellow()}measure#{ANSI.reset()}(#{ANSI.cyan()}:#{field}#{ANSI.reset()}, #{ANSI.magenta()}type:#{ANSI.reset()} #{ANSI.cyan()}:count_distinct#{ANSI.reset()}, #{ANSI.magenta()}name:#{ANSI.reset()} #{ANSI.cyan()}:#{field}_distinct#{ANSI.reset()})"
        ]
      end)

    float_measure_lines =
      float_fields
      |> Enum.map(fn {field, _} ->
        "  #{ANSI.yellow()}measure#{ANSI.reset()}(#{ANSI.cyan()}:#{field}#{ANSI.reset()}, #{ANSI.magenta()}type:#{ANSI.reset()} #{ANSI.cyan()}:sum#{ANSI.reset()}, #{ANSI.magenta()}name:#{ANSI.reset()} #{ANSI.cyan()}:#{field}_sum#{ANSI.reset()})"
      end)

    lines = lines ++ measure_lines ++ integer_measure_lines ++ float_measure_lines

    lines =
      lines ++
        [
          "#{ANSI.blue()}end#{ANSI.reset()}",
          ""
        ]

    Enum.join(lines, "\n")
  end

  # Helper function to generate auto-block for default cube
  defp generate_default_cube_block() do
    quote do
      # Get all Ecto fields at compile time
      ecto_fields = Module.get_attribute(__MODULE__, :ecto_fields)

      # Fields to skip (system fields)
      skip_fields = [:id, :inserted_at, :updated_at]

      # Filter out skipped fields
      user_fields =
        Enum.reject(ecto_fields, fn {field, _type} ->
          field in skip_fields
        end)

      # Generate dimensions for string and boolean fields
      for {field, {type, _}} <- user_fields,
          type in [:string, :binary, :binary_id, :bitstring, :boolean] do
        dimension(field)
      end

      # Generate dimensions for datetime/timestamp fields
      for {field, {type, _}} <- user_fields,
          type in [
            :naive_datetime,
            :naive_datetime_usec,
            :utc_datetime,
            :utc_datetime_usec,
            :date,
            :time,
            :time_usec
          ] do
        dimension(field)
      end

      # Always generate count measure
      measure(:count)

      # Generate sum AND count_distinct measures for integer fields
      for {field, {type, _}} <- user_fields, type in [:integer, :id] do
        # Sum measure
        measure(field,
          type: :sum,
          name: String.to_atom("#{field}_sum")
        )

        # Count distinct measure
        measure(field,
          type: :count_distinct,
          name: String.to_atom("#{field}_distinct")
        )
      end

      # Generate sum measures for float/decimal fields
      for {field, {type, _}} <- user_fields,
          type in [:float, :decimal] do
        measure(field,
          type: :sum,
          name: String.to_atom("#{field}_sum")
        )
      end
    end
  end

  # cube/2 - Auto-generates dimensions and measures when no block provided
  defmacro cube(cube_name, opts) do
    auto_generated_block = generate_default_cube_block()

    # Generate code to print the auto-generated cube source at compile time
    print_source_code =
      quote do
        ecto_fields = Module.get_attribute(__MODULE__, :ecto_fields)

        source_code =
          PowerOfThree.generate_cube_source_code(
            unquote(cube_name),
            unquote(opts),
            ecto_fields
          )

        IO.puts(source_code)
      end

    # Combine the print statement with the cube generation
    quote do
      unquote(print_source_code)
      unquote(cube(__CALLER__, cube_name, opts, auto_generated_block))
    end
  end

  # cube/3 - Explicit block provided
  defmacro cube(cube_name, opts, do: block) do
    cube(__CALLER__, cube_name, opts, block)
  end

  defp cube(caller, cube_name, opts, block) do
    prelude =
      quote do
        if line = Module.get_attribute(__MODULE__, :cube_defined) do
          raise "cube already defined for #{inspect(__MODULE__)} on line #{line}"
        end

        # |> IO.inspect(label: :cube_name)
        cube_name = unquote(cube_name)
        opts_ = unquote(opts)

        legit_cube_properties = [
          :pre_aggregations,
          :joins,
          :dimensions,
          :hierarchies,
          :segments,
          :access_policy,
          :extends,
          :sql_alias,
          :data_source,
          :sql_table,
          # [*] path through
          :title,
          # [*] path through 
          :description,
          # TODO path through
          :public,
          # TODO path through
          :refresh_key,
          # [ ] path through
          :meta
        ]

        # TODO use :context, :prefix, :source?
        {legit_opts, code_injection_attempeted} =
          Keyword.split(opts_, legit_cube_properties)

        Logger.error("Detected Inrusions list:  #{inspect(code_injection_attempeted)}")
        {sql_table, legit_opts} = legit_opts |> Keyword.pop(:sql_table)
        # |> IO.inspect(label: :cube_opts)
        cube_opts = Enum.into(legit_opts, %{})
        # TODO must match Ecto schema source

        case Module.get_attribute(__MODULE__, :ecto_fields, []) do
          [id: {:id, :always}] ->
            raise ArgumentError,
                  "Please `use Ecto.Schema` and define some fields first: Cube Dimensions/Measures need to reference ecto schema fields!"

          [] ->
            raise ArgumentError,
                  "Please `use Ecto.Schema` and define some fields first: Cube Dimensions/Measures need to reference ecto schema fields!"

          [_ | _] ->
            :ok
        end

        @cube_defined unquote(caller.line)
        Module.register_attribute(__MODULE__, :x_cube_primary_keys, accumulate: true)
        Module.register_attribute(__MODULE__, :x_measures, accumulate: true)
        Module.register_attribute(__MODULE__, :x_dimensions, accumulate: true)
        Module.register_attribute(__MODULE__, :x_time_dimensions, accumulate: true)
        Module.register_attribute(__MODULE__, :cube_enabled, persist: true)
        Module.put_attribute(__MODULE__, :cube_enabled, true)

        try do
          import PowerOfThree
          # |> IO.inspect(label: :schema_prefix)
          Module.get_attribute(__MODULE__, :schema_prefix)
          unquote(block)
        after
          :ok
        end
      end

    postlude =
      quote unquote: false do
        cube_primary_keys =
          @x_cube_primary_keys
          |> Enum.reverse()

        measures = @x_measures |> Enum.reverse()
        dimensions = @x_dimensions |> Enum.reverse()
        time_dimensions = @x_time_dimensions

        Module.register_attribute(__MODULE__, :cube_primary_keys, persist: true)

        Module.put_attribute(
          __MODULE__,
          :cube_primary_keys,
          cube_primary_keys
        )

        Module.register_attribute(__MODULE__, :measures, persist: true)

        Module.put_attribute(
          __MODULE__,
          :measures,
          measures
        )

        Module.register_attribute(__MODULE__, :dimensions, persist: true)

        Module.put_attribute(
          __MODULE__,
          :dimensions,
          dimensions
        )

        a_cube_config = [
          %{name: cube_name, sql_table: sql_table}
          |> Map.merge(cube_opts)
          |> Map.merge(%{dimensions: dimensions ++ time_dimensions, measures: measures})
        ]

        Module.register_attribute(__MODULE__, :cube_config, persist: true)

        Module.put_attribute(
          __MODULE__,
          :cube_config,
          a_cube_config
        )

        File.write(
          ("model/cubes/" <> Atom.to_string(cube_name) <> ".yaml")
          |> IO.inspect(label: :cube_config_file),
          %{cubes: a_cube_config}
          |> IO.inspect(label: :cube_config_file_content)
          |> Ymlr.document!()
        )

        # Generate Measures accessor module
        measures_module_name = Module.concat(__MODULE__, Measures)

        measures_functions =
          for measure <- measures do
            # Convert measure name to atom for function name
            measure_name =
              case measure.name do
                name when is_atom(name) -> name
                name when is_binary(name) -> String.to_atom(name)
              end

            # Generate function that returns MeasureRef
            quote do
              @doc """
              Returns a reference to the #{unquote(measure_name)} measure.

              ## Type
              #{unquote(measure.type)}

              ## Description
              #{unquote(measure[:description] || "No description available")}
              """
              def unquote(measure_name)() do
                %PowerOfThree.MeasureRef{
                  name: unquote(measure.name),
                  module: unquote(__MODULE__),
                  type: unquote(measure.type),
                  sql: unquote(Macro.escape(measure[:sql])),
                  meta: unquote(Macro.escape(measure[:meta])),
                  description: unquote(measure[:description]),
                  filters: unquote(Macro.escape(measure[:filters])),
                  format: unquote(measure[:format])
                }
              end
            end
          end

        # Create the Measures module
        Module.create(
          measures_module_name,
          quote do
            @moduledoc """
            Accessor module for measures in #{inspect(unquote(__MODULE__))}.

            Provides dot-accessible functions for each measure defined in the cube.

            ## Available Measures

            #{unquote(Enum.map_join(measures, "\n", fn m -> "  - `#{m.name}()` - #{m.type}" end))}
            """

            unquote_splicing(measures_functions)

            @doc "Lists all available measure names"
            def __measure_names__,
              do: unquote(Enum.map(measures, fn m -> m.name end))
          end,
          Macro.Env.location(__ENV__)
        )

        # Generate Dimensions accessor module
        dimensions_module_name = Module.concat(__MODULE__, Dimensions)

        # time_dimensions is an accumulated list (may be empty)
        time_dimensions_list = time_dimensions |> Enum.reverse()

        all_dimensions = dimensions ++ time_dimensions_list

        dimensions_functions =
          for dimension <- all_dimensions do
            # Convert dimension name to atom for function name
            dimension_name =
              case dimension.name do
                name when is_atom(name) -> name
                name when is_binary(name) -> String.to_atom(name)
              end

            # Generate function that returns DimensionRef
            quote do
              @doc """
              Returns a reference to the #{unquote(dimension_name)} dimension.

              ## Type
              #{unquote(dimension.type)}

              ## Description
              #{unquote(dimension[:description] || "No description available")}
              """
              def unquote(dimension_name)() do
                %PowerOfThree.DimensionRef{
                  name: unquote(dimension.name),
                  module: unquote(__MODULE__),
                  type: unquote(dimension.type),
                  sql: unquote(to_string(dimension.sql)),
                  meta: unquote(Macro.escape(dimension[:meta])),
                  description: unquote(dimension[:description]),
                  primary_key: unquote(dimension[:primary_key] || false),
                  format: unquote(dimension[:format]),
                  propagate_filters_to_sub_query:
                    unquote(dimension[:propagate_filters_to_sub_query]),
                  public: unquote(dimension[:public])
                }
              end
            end
          end

        # Create the Dimensions module
        Module.create(
          dimensions_module_name,
          quote do
            @moduledoc """
            Accessor module for dimensions in #{inspect(unquote(__MODULE__))}.

            Provides dot-accessible functions for each dimension defined in the cube.

            ## Available Dimensions

            #{unquote(Enum.map_join(all_dimensions, "\n", fn d -> "  - `#{d.name}()` - #{d.type}" end))}
            """

            unquote_splicing(dimensions_functions)

            @doc "Lists all available dimension names"
            def __dimension_names__,
              do: unquote(Enum.map(all_dimensions, fn d -> d.name end))
          end,
          Macro.Env.location(__ENV__)
        )

        # Generate accessor functions in the main module
        def measures do
          unquote(
            for measure <- measures do
              measure_name =
                case measure.name do
                  name when is_atom(name) -> name
                  name when is_binary(name) -> String.to_atom(name)
                end

              quote do
                unquote(measures_module_name).unquote(measure_name)()
              end
            end
          )
        end

        def dimensions do
          unquote(
            for dimension <- all_dimensions do
              dimension_name =
                case dimension.name do
                  name when is_atom(name) -> name
                  name when is_binary(name) -> String.to_atom(name)
                end

              quote do
                unquote(dimensions_module_name).unquote(dimension_name)()
              end
            end
          )
        end

        @doc """
        Queries the cube and returns results as a DataFrame (if Explorer is available) or map.

        Supports two connection modes:
        - **HTTP** (default) - REST API, works in any Elixir environment
        - **ADBC** - High-performance Arrow protocol via native driver

        ## Options

          * `:columns` - Required. List of MeasureRef and/or DimensionRef structs
          * `:where` - Optional. SQL WHERE clause (without "WHERE" keyword). HTTP mode supports simple filters only.
          * `:order_by` - Optional. List of `{column_index, :asc | :desc}` or just `column_index`
          * `:limit` - Optional. Maximum number of rows to return
          * `:offset` - Optional. Number of rows to skip
          * `:connection` - Optional. Existing ADBC connection (enables ADBC mode)
          * `:connection_opts` - Optional. Options for creating a new connection (HTTP by default)
          * `:connection_type` - Optional. `:http` (default) or `:adbc`
          * `:http_client` - Optional. Existing HTTP client (enables HTTP mode)

        ## Examples

            # Simple query using HTTP (default)
            df = Customer.df(columns: [
              Customer.Dimensions.brand(),
              Customer.Measures.count()
            ])

            # Specify HTTP connection options
            df = Customer.df(
              columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
              connection_opts: [base_url: "http://localhost:4008", api_token: "secret"]
            )

            # Reusing HTTP client
            {:ok, http_client} = PowerOfThree.CubeHttpClient.new(base_url: "http://localhost:4008")
            df = Customer.df(columns: [...], http_client: http_client)

            # Using ADBC mode (for complex queries or better performance)
            df = Customer.df(
              columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
              connection_type: :adbc,
              connection_opts: [token: "my-token"]
            )

            # Using list-based accessors
            dimensions = Customer.dimensions()  # Returns list of all DimensionRef structs
            measures = Customer.measures()      # Returns list of all MeasureRef structs

            brand = Enum.find(dimensions, fn d -> d.name == :brand end)
            count = Enum.find(measures, fn m -> m.name == "count" or m.name == :count end)

            df = Customer.df(columns: [brand, count])

            # With filters and ordering
            df = Customer.df(
              columns: [Customer.Dimensions.email(), Customer.Measures.count()],
              where: "brand_code = 'NIKE'",
              order_by: [{2, :desc}],
              limit: 10
            )

            # Reusing an ADBC connection
            {:ok, conn} = PowerOfThree.CubeConnection.connect(token: "my-token")
            df = Customer.df(columns: [...], connection: conn)

        ## HTTP Mode Limitations (Default)

        HTTP mode supports simple WHERE clauses only:
        - Equals: `field = 'value'`
        - Not equals: `field != 'value'`
        - Comparison: `field > 100`, `field <= 50`
        - Set membership: `field IN ('a', 'b', 'c')`

        Complex WHERE clauses with AND/OR/NOT require ADBC mode.
        For complex queries, specify `connection_type: :adbc`.
        """
        def df(opts) do
          cube_name = unquote(cube_name) |> to_string()
          _columns = Keyword.fetch!(opts, :columns)

          query_opts =
            opts
            |> Keyword.put(:cube, cube_name)
            |> Keyword.take([:cube, :columns, :where, :order_by, :limit, :offset])

          # Determine connection mode (HTTP or ADBC)
          case determine_connection_mode(opts) do
            {:http, http_opts} ->
              execute_http_query(query_opts, http_opts)

            {:adbc, adbc_opts} ->
              execute_adbc_query(query_opts, adbc_opts)
          end
        end

        # Determines whether to use HTTP or ADBC based on options
        defp determine_connection_mode(opts) do
          cond do
            # Explicit HTTP client provided
            Keyword.has_key?(opts, :http_client) ->
              {:http, Keyword.get(opts, :http_client)}

            # Explicit ADBC connection provided
            Keyword.has_key?(opts, :connection) ->
              {:adbc, opts}

            # Explicit connection type specified
            Keyword.get(opts, :connection_type) == :adbc ->
              {:adbc, opts}

            Keyword.get(opts, :connection_type) == :http ->
              http_opts = Keyword.get(opts, :connection_opts, [])
              {:http, http_opts}

            # Default to HTTP
            true ->
              http_opts = Keyword.get(opts, :connection_opts, [])
              {:http, http_opts}
          end
        end

        # Executes query via HTTP API
        defp execute_http_query(query_opts, http_opts) do
          with {:ok, client} <- get_or_create_http_client(http_opts),
               {:ok, cube_query} <-
                 PowerOfThree.CubeQueryTranslator.to_cube_query(query_opts),
               {:ok, result_map} <- PowerOfThree.CubeHttpClient.query(client, cube_query) do
            {:ok, PowerOfThree.CubeFrame.from_result(result_map)}
          end
        end

        # Gets existing HTTP client or creates new one
        defp get_or_create_http_client(client) when is_struct(client) do
          {:ok, client}
        end

        defp get_or_create_http_client(opts) when is_list(opts) do
          PowerOfThree.CubeHttpClient.new(opts)
        end

        # Executes query via ADBC
        defp execute_adbc_query(query_opts, opts) do
          sql = PowerOfThree.QueryBuilder.build(query_opts)

          # Get or create connection
          conn =
            case Keyword.get(opts, :connection) do
              nil ->
                conn_opts = Keyword.get(opts, :connection_opts, [])

                case PowerOfThree.CubeConnection.connect(conn_opts) do
                  {:ok, conn} -> conn
                  {:error, error} -> {:error, error}
                end

              conn ->
                conn
            end

          case conn do
            {:error, _} = error ->
              error

            conn ->
              case PowerOfThree.CubeConnection.query_to_map(conn, sql) do
                {:ok, result_map} ->
                  {:ok, PowerOfThree.CubeFrame.from_result(result_map)}

                {:error, _} = error ->
                  error
              end
          end
        end

        @doc """
        Queries the cube and returns results, raising on error.

        See `df/1` for options and examples.
        """
        def df!(opts) do
          case df(opts) do
            {:ok, result} -> result
            {:error, error} -> raise error
          end
        end

        # |> IO.inspect(label: :a_cube_config)
        # a_cube_config
        :ok
      end

    quote do
      unquote(prelude)
      unquote(postlude)
    end
  end

  @doc """
  Uses `:inserted_at` as default time dimension
  defmacro cube(__CALLER__,cube_name, what_ecto_schema, block)

  defp cube(caller,cube_name,what_ecto_schema, block) do
  """
  defmacro time_dimensions(cube_date_time_fields \\ []) do
    quote bind_quoted: binding() do
      Module.put_attribute(
        __MODULE__,
        :x_time_dimensions,
        %{
          meta: %{ecto_field: :inserted_at},
          name: :inserted_at,
          type: :time,
          sql: :inserted_at,
          description: "inserted_at"
        }
      )
    end
  end

  @doc """

  Dimension first argument takes a single Ecto.Schema field or a list of Ecto.Schema fields.

  Lets create a Dimension for several Ecto.Schema fields. A list of Ecto.Schema fields is mandatory.
  Ecto.Schema fields concatenated into SQL: `brand_code||market_code||email`
  The `primary_key: true` tells the cube how to distinguish unique records.

  ## Examples


      dimension(
        [:brand_code, :market_code, :email],
        name: :email_per_brand_per_market,
        primary_key: true
      )


  Lets create a Dimension for a single Ecto.Schema field

  ## Examples


      dimension(:brand_code, name: :brand, description: "Beer")

  """

  defmacro dimension(ecto_schema_field_or_list_of_fields, opts \\ [])

  defmacro dimension(
             list_of_ecto_schema_fields,
             opts
           )
           when is_list(list_of_ecto_schema_fields) do
    quote bind_quoted: binding() do
      # |> IO.inspect(label: :d_schema_prefix)
      Module.get_attribute(__MODULE__, :schema_prefix)

      intersection =
        for ecto_field <- Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)),
            ecto_field in list_of_ecto_schema_fields,
            do: ecto_field

      case list_of_ecto_schema_fields |> Enum.sort() == intersection |> Enum.sort() do
        false ->
          raise ArgumentError,
                "Cube Dimension wants all of: #{inspect(list_of_ecto_schema_fields)}, \n" <>
                  "But only these are avalable: #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}\n" <>
                  "The suspects of not to be known Ecto `field` are:  #{inspect(list_of_ecto_schema_fields -- intersection)}"

        true ->
          path_throw_opts = opts |> Keyword.drop([:sql, :name, :type]) |> Enum.into(%{})
          type = opts[:type] || opts[:type] |> dimension_type

          sql =
            opts[:sql] ||
              list_of_ecto_schema_fields
              |> Enum.map_join("||", fn atom -> atom |> Atom.to_string() end)

          dimension_name =
            opts[:name] ||
              list_of_ecto_schema_fields
              |> Enum.map_join("_", fn atom -> atom |> Atom.to_string() end)

          case opts[:primary_key] || false do
            true ->
              Module.put_attribute(
                __MODULE__,
                :x_cube_primary_keys,
                sql
              )

            false ->
              :ok
          end

          Module.put_attribute(
            __MODULE__,
            :x_dimensions,
            path_throw_opts
            |> Map.merge(%{
              # TODO respect meta in path_throw_opts
              meta: %{ecto_fields: list_of_ecto_schema_fields},
              name: dimension_name,
              type: type,
              sql: sql
            })
          )
      end
    end
  end

  defmacro dimension(ecto_schema_field, opts) do
    quote bind_quoted: binding() do
      case Keyword.get(Module.get_attribute(__MODULE__, :ecto_fields), ecto_schema_field, false) do
        false ->
          raise ArgumentError,
                "Cube Dimension wants a #{inspect(ecto_schema_field)}, but Ecto schema has only: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        {ecto_field_type, _always} ->
          path_throw_opts = opts |> Keyword.drop([:sql, :name, :type]) |> Enum.into(%{})

          Module.put_attribute(
            __MODULE__,
            :x_dimensions,
            path_throw_opts
            |> Map.merge(%{
              meta: %{
                ecto_field_type:
                  case ecto_field_type do
                    {:parameterized, {Ecto.Enum, _parameterized}} -> :string
                    _ -> ecto_field_type
                  end,
                ecto_field: ecto_schema_field
              },
              name: opts[:name] || ecto_schema_field |> Atom.to_string(),
              type: opts[:type] || ecto_field_type |> dimension_type,
              sql: ecto_schema_field |> Atom.to_string()
            })
          )
      end
    end
  end

  @doc """

  Measure first argument takes an atom `:count`, a single Ecto.Schema field or a list of Ecto.Schema fields.


  Lets create a Measure for several Ecto.Schema fields. A list of Ecto.Schema fields reference and `:type` are mandatory.
  The `sql:` is mandatory, must be valid SQL clause using the fields from list and returning a number.

  ## Examples

      measure([:tax_amount,:discount_total_amount],
        sql: "tax_amount + discount_total_amount",
        type: :sum,
        description: "two measures we want add together"
      )


  Lets create a Measure for a single Ecto.Schema field
  The Ecto.Schema field reference and `:type` are mandatory
  The other cube measure DLS properties are passed through

  ## Examples


      measure(:email,
        name: :emails_distinct,
        type: :count_distinct,
        description: "count distinct of emails"
      )


  Lets create a Measure of type `:count`
  No `:type` is needed
  The other cube measure DLS properties are passed through

  ## Examples


      measure(:count,
        description: "no need for fields for :count type measure"
      )

  """

  defmacro measure(
             atom_count_ecto_field_or_list,
             opts \\ []
           )

  defmacro measure(
             for_ecto_fields,
             opts
           )
           when is_list(for_ecto_fields) do
    quote bind_quoted: binding() do
      intersection =
        for ecto_field <- Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)),
            ecto_field in for_ecto_fields,
            do: ecto_field

      case for_ecto_fields |> Enum.sort() == intersection |> Enum.sort() do
        false ->
          raise ArgumentError,
                "Cube Measure wants all of: #{inspect(for_ecto_fields |> Enum.sort())}, \n" <>
                  "But only these are avalable: #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)) |> Enum.sort())}\n" <>
                  "The suspects of not to be known Ecto `field` are:  #{inspect((for_ecto_fields -- intersection) |> Enum.sort())}"

        true ->
          sql =
            opts[:sql] ||
              raise ArgumentError,
                    "Cube Measure uses multiple fields: \n#{inspect(for_ecto_fields)},\n, hence the`:sql` clause returning a number is mandatory. It is not provided in opts: \n #{inspect(opts)}"

          path_throw_opts = opts |> Keyword.drop([:sql, :name, :type]) |> Enum.into(%{})

          Module.put_attribute(
            __MODULE__,
            :x_measures,
            path_throw_opts
            |> Map.merge(%{
              name:
                opts[:name] ||
                  for_ecto_fields |> Enum.map_join("_", fn atom -> atom |> Atom.to_string() end),
              type: :number,
              sql: sql
            })
          )
      end
    end
  end

  defmacro measure(
             :count,
             opts
           ) do
    quote bind_quoted: binding() do
      path_throw_opts = opts |> Keyword.drop([:type]) |> Enum.into(%{})

      Module.put_attribute(
        __MODULE__,
        :x_measures,
        path_throw_opts
        |> Map.merge(%{
          name: opts[:name] || :count,
          type: :count
        })
      )
    end
  end

  defmacro measure(
             for_ecto_field,
             opts
           ) do
    quote bind_quoted: binding() do
      case Keyword.get(Module.get_attribute(__MODULE__, :ecto_fields), for_ecto_field, false) do
        false ->
          raise ArgumentError,
                "Cube Measure wants: \n#{inspect(for_ecto_field)},\n but only these found: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        {ecto_type, _ecto_always} ->
          type =
            opts[:type] ||
              raise ArgumentError,
                    "The `:type` is required in opts for Cube Measure that uses single field: #{inspect(for_ecto_field)},\n the opts are: #{inspect(opts)}"

          # TODO rize on invalid measure types
          # measure_types = PowerOfThree, :measure_types)
          # type in measure_types || raise ArgumentError,
          #  "The `:type` #{inspect(opts[:type])} is not valid, \n the valid types are: #{inspect(measure_types)}"

          path_throw_opts = opts |> Keyword.drop([:type]) |> Enum.into(%{})

          Module.put_attribute(
            __MODULE__,
            :x_measures,
            path_throw_opts
            |> Map.merge(%{
              name: opts[:name] || for_ecto_field |> Atom.to_string(),
              type: type,
              sql: for_ecto_field,
              meta: %{ecto_field: for_ecto_field, ecto_type: ecto_type}
            })
          )
      end
    end
  end

  @spec dimension_type(any()) :: :boolen | :number | :string | :time
  @doc false
  def dimension_type(ecto_field_type) do
    cond do
      ecto_field_type in [:bitstring, :string, :binary_id, :binary] ->
        :string

      ecto_field_type in [
        :date,
        :time,
        :time_usec,
        :naive_datetime,
        :naive_datetime_usec,
        :utc_datetime,
        :utc_datetime_usec
      ] ->
        :time

      ecto_field_type in [
        :id,
        :integer,
        :float,
        :decimal
      ] ->
        :number

      ecto_field_type in [
        :boolean
      ] ->
        :boolen

      true ->
        :string
    end
  end
end
