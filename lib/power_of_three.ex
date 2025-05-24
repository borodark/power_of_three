defmodule PowerOfThree do
  @moduledoc """

  TODO - handle schema, prefix, table should Xsist
  TODO - one arg measure[:count], dimension[:string] for a column name 

  Able to generate cube.dev config files for cubes defined for one `using Ecto.Schema`.
  The dimensions and measures derive some defaults
  from `Ecto.Schema.field` properties mentioned in the defenition

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

  """
  defmacro __using__(_) do
    quote do
      import PowerOfThree,
        only: [cube: 3, dimension: 2, measure: 3, measure: 2, time_dimensions: 1]

      Module.register_attribute(__MODULE__, :cube_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :measures, accumulate: true)
      Module.register_attribute(__MODULE__, :dimensions, accumulate: true)
      Module.register_attribute(__MODULE__, :time_dimensions, accumulate: true)
      Module.put_attribute(__MODULE__, :cube_enabled, true)
    end
  end

  defmacro cube(cube_name, opts, do: block) do
    cube(__CALLER__, cube_name, opts, block)
  end

  @cube_properties [
    # :name, 1st argument
    # :pre_aggregations,
    # :joins,
    # :dimensions,
    # :hierarchies,
    # :segments,
    # :measures,
    # :access_policy
    # TODO? :extends,
    :sql_alias,
    :data_source,
    :sql,
    :sql_table,
    :title,
    :description,
    :public,
    :refresh_key,
    :meta
  ]

  defp cube(caller, cube_name, opts, block) do
    prelude =
      quote do
        if line = Module.get_attribute(__MODULE__, :cube_defined) do
          raise "cube already defined for #{inspect(__MODULE__)} on line #{line}"
        end

        cube_name = unquote(cube_name) |> IO.inspect(label: :cube_name)
        extra_opts = unquote(opts)

        {cube_opts_, _} =
          Keyword.split(extra_opts, [
            :sql_alias,
            :data_source,
            :sql,
            :sql_table,
            :title,
            :description,
            :public,
            :refresh_key,
            :meta
          ])

        cube_opts = Enum.into(cube_opts_, %{}) |> IO.inspect(label: :cube_opts)
        sql_table = cube_opts[:sql_table]
        # TODO must match Ecto schema source 
        case Module.get_attribute(__MODULE__, :ecto_fields, []) do
          [id: {:id, :always}] ->
            raise ArgumentError,
                  "Cube Dimensions/Measures need ecto schema fields! Please `use Ecto.Schema` and define some fields first ..."

          [] ->
            raise ArgumentError,
                  "Cube Dimensions/Measures need ecto schema fields! Please `use Ecto.Schema` and define some fields Ofirst ..."

          [_ | _] ->
            :ok
        end

        @cube_defined unquote(caller.line)

        Module.register_attribute(__MODULE__, :cube_primary_keys, accumulate: true)
        Module.register_attribute(__MODULE__, :measures, accumulate: true)
        Module.register_attribute(__MODULE__, :dimensions, accumulate: true)
        Module.register_attribute(__MODULE__, :datetime_dimensions, accumulate: true)
        Module.put_attribute(__MODULE__, :cube_enabled, true)

        try do
          import PowerOfThree
          unquote(block)
        after
          :ok
        end
      end

    postlude =
      quote unquote: false do
        cube_primary_keys =
          @cube_primary_keys
          |> Enum.reverse()

        measures = @measures |> Enum.reverse()
        dimensions = @dimensions
        time_dimensions = @time_dimensions

        a_cube_config = [
          %{name: cube_name}
          |> Map.merge(cube_opts)
          |> Map.merge(%{dimensions: dimensions ++ time_dimensions, measures: measures})
        ]

        # TODO validate sql_table
        File.write(
          ("model/cubes/cubes-of-" <> sql_table <> ".yaml") |> IO.inspect(label: :file_name),
          %{cubes: a_cube_config}
          |> Ymlr.document!()
        )

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
        :time_dimensions,
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

  defmacro dimension(ecto_schema_field_or_list_of_fields, opts \\ [])
  # TODO change to dimension(:ecto_fileld <- becomes sql:, [name[m]: dim_name, ...] 
  defmacro dimension(
             list_of_ecto_schema_fields,
             opts
           )
           when is_list(list_of_ecto_schema_fields) and length(list_of_ecto_schema_fields) > 1 do
    quote bind_quoted: binding() do
      intersection =
        for ecto_field <- Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)),
            ecto_field in list_of_ecto_schema_fields,
            do: ecto_field

      case list_of_ecto_schema_fields |> Enum.sort() == intersection |> Enum.sort() do
        false ->
          # TODO use all info in error message
          raise ArgumentError,
                "Cube Dimension wants all of: #{inspect(list_of_ecto_schema_fields)}," <>
                  "But only these are avalable:\n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        true ->
          # TODO our_opts = take_our_opts() 
          type = opts[:type] || :string

          sql =
            opts[:sql] ||
              list_of_ecto_schema_fields
              |> Enum.map(fn atom -> atom |> Atom.to_string() end)
              |> Enum.join("||")

          desc = opts[:description] || "Documentation if Empathy"

          dimension_name =
            opts[:name] ||
              list_of_ecto_schema_fields
              |> Enum.map(fn atom -> atom |> Atom.to_string() end)
              |> Enum.join("_")

          # TODO all properties
          Module.put_attribute(
            __MODULE__,
            :dimensions,
            %{
              meta: %{ecto_fields: list_of_ecto_schema_fields},
              name: dimension_name,
              type: type,
              sql: sql,
              description: desc
            }
          )
      end
    end
  end

  # TODO perhaps handle ecto_schema_field = [:some_cleaver_guy_trying_to_being_literal]
  defmacro dimension(ecto_schema_field, opts) do
    quote bind_quoted: binding() do
      case Keyword.get(Module.get_attribute(__MODULE__, :ecto_fields), ecto_schema_field, false) do
        false ->
          raise ArgumentError,
                "Cube Dimension wants a #{inspect(ecto_schema_field)}, but Ecto schema has only: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        {original_ecto_field_type, _always} ->
          type =
            opts[:type] ||
              cond do
                original_ecto_field_type in [:bitstring, :string, :binary_id, :binary] ->
                  :string

                original_ecto_field_type in [
                  :date,
                  :time,
                  :time_usec,
                  :naive_datetime,
                  :naive_datetime_usec,
                  :utc_datetime,
                  :utc_datetime_usec
                ] ->
                  :time

                original_ecto_field_type in [
                  :id,
                  :integer,
                  :float,
                  :decimal
                ] ->
                  :number

                original_ecto_field_type in [
                  :boolean
                ] ->
                  :boolen

                true ->
                  :string
              end

          dimension_name = opts[:name] || ecto_schema_field |> Atom.to_string()
          sql = ecto_schema_field |> Atom.to_string()
          desc = "Dimension " <> Atom.to_string(ecto_schema_field)

          original_ecto_field_type =
            case original_ecto_field_type do
              {:parameterized, {Ecto.Enum, _parameterized}} -> :string
              _ -> original_ecto_field_type
            end

          Module.put_attribute(
            __MODULE__,
            :dimensions,
            %{
              meta: %{
                ecto_field_type: original_ecto_field_type,
                ecto_field: ecto_schema_field
              },
              name: dimension_name,
              type: type,
              sql: sql,
              description: desc
            }
          )
      end
    end
  end

  defmacro measure(
             measure_name,
             opts
           )
           when is_list(opts) and length(opts) > 1 do
    # TODO , opts \\ []

    quote bind_quoted: binding() do
      case opts[:type] == :count do
        true ->
          desc = opts[:description] || "Documentation if Empathy"

          Module.put_attribute(
            __MODULE__,
            :measures,
            %{
              name: measure_name,
              type: :count,
              # add meta
              description: desc
            }
          )

        false ->
          raise ArgumentError,
                "The Measure #{inspect(measure_name)} is not of type `:count` and second argument `field/fields` is/are reqiured."
      end
    end
  end

  defmacro measure(
             measure_name,
             for_ecto_fields,
             opts
           )
           when is_list(for_ecto_fields) and length(for_ecto_fields) > 1 do
    quote bind_quoted: binding() do
      intersection =
        for ecto_field <- Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)),
            ecto_field in for_ecto_fields,
            do: ecto_field

      case for_ecto_fields |> Enum.sort() == intersection |> Enum.sort() do
        false ->
          raise ArgumentError,
                "Cube Measure wants: \n#{inspect(for_ecto_fields)},\n but only those found: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        true ->
          type = :number

          sql =
            opts[:sql] ||
              raise ArgumentError,
                    "Cube Measure uses multiple fields: \n#{inspect(for_ecto_fields)},\n, hence the`:sql` is mandatory, but not provided in opts: \n #{inspect(opts)}"

          desc = opts[:description] || "Documentation if Empathy"

          Module.put_attribute(
            __MODULE__,
            :measures,
            %{
              name: measure_name,
              type: type,
              sql: sql,
              description: desc
              # meta: %{ecto_fields: for_ecto_fields}
            }
          )
      end
    end
  end

  defmacro measure(
             measure_name,
             for_ecto_field,
             opts
           ) do
    quote bind_quoted: binding() do
      case Keyword.get(Module.get_attribute(__MODULE__, :ecto_fields), for_ecto_field, false) do
        false ->
          raise ArgumentError,
                "Cube Measure wants: \n#{inspect(for_ecto_field)},\n but only those found: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        {ecto_type, _ecto_always} ->
          type =
            opts[:type] ||
              raise ArgumentError,
                    "The `:type` is required in options for Cube Measure that uses a single field: \n#{inspect(for_ecto_field)},\n opts: \n #{inspect(opts)}"

          desc = opts[:description] || "Documentation if Empathy"

          Module.put_attribute(
            __MODULE__,
            :measures,
            %{
              name: measure_name,
              type: type,
              sql: for_ecto_field,
              description: desc,
              meta: %{ecto_field: for_ecto_field, ecto_type: ecto_type}
            }
          )
      end
    end
  end

  defmodule Dimension do
    @moduledoc """
    https://cube.dev/docs/reference/data-model/dimensions
    A Dimension of Cube object with following properties:
    Parameters:
      - name
      - case
      - description
      - format
      - meta
      - primary_key
      - propagate_filters_to_sub_query
      - public
      - sql
      - sub_query
      - title
      - type
      - granularities
    """
    @case [when: [], else: nil]
    @dimension_type [:string, :time, :number, :boolean, :geo]
    @format [:imageUrl, :id, :link, :currency, :percent]
    @parameters [
      :name,
      :case,
      :description,
      :format,
      :meta,
      :public,
      :sql,
      :title,
      :type,
      :granularities
    ]
  end

  defmodule Measure do
    @moduledoc """
    https://cube.dev/docs/reference/data-model/measures
    A Measure of Cube object with following:
    Parameters:
      - name
      - description
      - drill_members
      - filters
      - format @format
      - meta
      - rolling_window @rolling_window
      - public
      - sql
      - title
      - type  @type
    """

    @measure_types [
      # string can be used as categorical if :sql converts a numerical value to
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

    @format [:percent, :currency]

    @rolling_window [:trailing, :leading]
    # These parameters have a format defined as (-?\d+) (minute|hour|day|week|month|year)

    @mandatory [:name, :sql, :type]
    @defaults [
      name: nil,
      sql: nil,
      type: :count,
      title: nil,
      description: nil,
      # drill_members is defined as an array of dimensions
      drill_members: [],
      filters: [],
      format: nil,
      meta: [tag: :measure],
      rolling_window: nil,
      public: true
    ]
  end

  def define() do
  end
end
