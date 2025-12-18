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
        only: [cube: 3, dimension: 2, measure: 2, time_dimensions: 1]

      require Logger

      Module.register_attribute(__MODULE__, :cube_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :measures, accumulate: true)
      Module.register_attribute(__MODULE__, :dimensions, accumulate: true)
      Module.register_attribute(__MODULE__, :time_dimensions, accumulate: true)
      Module.put_attribute(__MODULE__, :cube_enabled, true)
      #
    end
  end

  defmacro cube(cube_name, opts, do: block) do
    cube(__CALLER__, cube_name, opts, block)
  end

  defp cube(caller, cube_name, opts, block) do
    prelude =
      quote do
        if line = Module.get_attribute(__MODULE__, :cube_defined) do
          raise "cube already defined for #{inspect(__MODULE__)} on line #{line}"
        end

        cube_name = unquote(cube_name) |> IO.inspect(label: :cube_name)
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
        cube_opts = Enum.into(legit_opts, %{}) |> IO.inspect(label: :cube_opts)
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
          Module.get_attribute(__MODULE__, :schema_prefix) |> IO.inspect(label: :schema_prefix)
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
          ("model/cubes/cubes-of-" <> sql_table <> ".yaml") |> IO.inspect(label: :file_name),
          %{cubes: a_cube_config}
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
        def measures, do: unquote(measures_module_name)
        def dimensions, do: unquote(dimensions_module_name)

        @doc """
        Queries the cube and returns results as a DataFrame (if Explorer is available) or map.

        ## Options

          * `:columns` - Required. List of MeasureRef and/or DimensionRef structs
          * `:where` - Optional. SQL WHERE clause (without "WHERE" keyword)
          * `:order_by` - Optional. List of `{column_index, :asc | :desc}` or just `column_index`
          * `:limit` - Optional. Maximum number of rows to return
          * `:offset` - Optional. Number of rows to skip
          * `:connection` - Optional. Existing ADBC connection (creates new if not provided)
          * `:connection_opts` - Optional. Options for creating a new connection

        ## Examples

            # Simple query
            df = Customer.df(columns: [
              Customer.dimensions().brand(),
              Customer.measures().count()
            ])

            # With filters and ordering
            df = Customer.df(
              columns: [Customer.dimensions().email(), Customer.measures().count()],
              where: "brand_code = 'NIKE'",
              order_by: [{2, :desc}],
              limit: 10
            )

            # Reusing a connection
            {:ok, conn} = PowerOfThree.CubeConnection.connect(token: "my-token")
            df = Customer.df(columns: [...], connection: conn)
        """
        def df(opts) do
          cube_name = unquote(cube_name) |> to_string()
          columns = Keyword.fetch!(opts, :columns)

          query_opts =
            opts
            |> Keyword.put(:cube, cube_name)
            |> Keyword.take([:cube, :columns, :where, :order_by, :limit, :offset])

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
                  {:ok, PowerOfThree.DataFrame.from_result(result_map)}

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

        a_cube_config |> IO.inspect(label: :a_cube_config)
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
      Module.get_attribute(__MODULE__, :schema_prefix) |> IO.inspect(label: :d_schema_prefix)

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
          name: opts[:name] || "count",
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

          # TODO measure_types = PowerOfThree, :measure_types)
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

  @dimension_opts [
    name: :string,
    case: [when: [], else: nil],
    description: :string,
    format: [:imageUrl, :id, :link, :currency, :percent],
    meta: [],
    primary_key: :boolean,
    propagate_filters_to_sub_query: :boolean,
    public: :boolean,
    sql: :string,
    sub_query: :string,
    title: :string,
    type: [:string, :time, :number, :boolean, :geo],
    granularities: []
  ]

  @measure_required [:name, :sql, :type]
  @measure_types [
    :string,
    :time,
    :boolean,
    :number,
    :count,
    :count_distinct,
    :count_distinct_approx,
    :sum,
    :avg,
    :min,
    :max
  ]
  @measure_all [
    name: :atom,
    sql: :string,
    type: @measure_types,
    title: :string,
    description: :string,
    # drill_members is defined as an array of dimensions
    drill_members: [],
    filters: [],
    format: [:percent, :currency],
    meta: [tag: :measure],
    rolling_window: [:trailing, :leading],
    # These parameters have a format defined as (-?\d+) (minute|hour|day|week|month|year)
    public: true
  ]
end
