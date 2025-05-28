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
        only: [cube: 3, dimension: 2, measure: 2, time_dimensions: 1]

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
          :sql,
          :sql_table,
          :title,
          :description,
          :public,
          :refresh_key,
          :meta
        ]

        {legit_opts, code_injection_attempeted} =
          Keyword.split(opts_, legit_cube_properties)

        require Logger
        Logger.error("Inrusions detected list:  #{inspect(code_injection_attempeted)}")
        cube_opts = Enum.into(legit_opts, %{}) |> IO.inspect(label: :cube_opts)
        # TODO must match Ecto schema source
        sql_table = cube_opts[:sql_table]
        # TODO sql = cube_opts[:sql]
        # TODO error out on either sql OR sql_table
        case Module.get_attribute(__MODULE__, :ecto_fields, []) do
          [id: {:id, :always}] ->
            raise ArgumentError,
                  "Cube Dimensions/Measures need ecto schema fields! Please `use Ecto.Schema` and define some fields first ..."

          [] ->
            raise ArgumentError,
                  "Cube Dimensions/Measures need ecto schema fields! Please `use Ecto.Schema` and define some fields first ..."

          [_ | _] ->
            :ok
        end

        @cube_defined unquote(caller.line)

        Module.register_attribute(__MODULE__, :cube_primary_keys, accumulate: true)
        Module.register_attribute(__MODULE__, :measures, accumulate: true)
        Module.register_attribute(__MODULE__, :dimensions, accumulate: true)
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
        dimensions = @dimensions |> Enum.reverse()
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

  defmacro dimension(
             list_of_ecto_schema_fields,
             opts
           )
           when is_list(list_of_ecto_schema_fields) do
    quote bind_quoted: binding() do
      intersection =
        for ecto_field <- Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)),
            ecto_field in list_of_ecto_schema_fields,
            do: ecto_field

      case list_of_ecto_schema_fields |> Enum.sort() == intersection |> Enum.sort() do
        false ->
          raise ArgumentError,
                "Cube Dimension wants all of: #{inspect(list_of_ecto_schema_fields)}, \n" <>
                  "But only these are avalable: #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

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

          # TODO all properties
          Module.put_attribute(
            __MODULE__,
            :dimensions,
            path_throw_opts
            |> Map.merge(%{
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
            :dimensions,
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
                "Cube Measure wants: \n#{inspect(for_ecto_fields)},\n but only those found: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        true ->
          sql =
            opts[:sql] ||
              raise ArgumentError,
                    "Cube Measure uses multiple fields: \n#{inspect(for_ecto_fields)},\n, hence the`:sql` clause returning a number is mandatory. It is not provided in opts: \n #{inspect(opts)}"

          Module.put_attribute(
            __MODULE__,
            :measures,
            %{
              name:
                opts[:name] ||
                  for_ecto_fields |> Enum.map_join("_", fn atom -> atom |> Atom.to_string() end),
              type: :number,
              sql: sql,
              description: opts[:description] || "Documentation if Empathy"
            }
          )
      end
    end
  end

  defmacro measure(
             :count,
             opts
           ) do
    quote bind_quoted: binding() do
      Module.put_attribute(
        __MODULE__,
        :measures,
        %{
          name: opts[:name] || "count",
          type: :count,
          description: opts[:description] || "Documentation if Empathy",
          title: opts[:title] || "Title would be nice"
        }
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
                "Cube Measure wants: \n#{inspect(for_ecto_field)},\n but only those found: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        {ecto_type, _ecto_always} ->
          type =
            opts[:type] ||
              raise ArgumentError,
                    "The `:type` is required in opts for Cube Measure that uses single field: #{inspect(for_ecto_field)},\n opts are: #{inspect(opts)}"

          desc = opts[:description] || "Documentation if Empathy"

          Module.put_attribute(
            __MODULE__,
            :measures,
            %{
              name: opts[:name] || for_ecto_field |> Atom.to_string(),
              type: type,
              sql: for_ecto_field,
              description: desc,
              meta: %{ecto_field: for_ecto_field, ecto_type: ecto_type}
            }
          )
      end
    end
  end

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

    @parameters [
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
  end

  @measure_required [:name, :sql, :type]
  @measure_all [
    name: :atom,
    sql: :string,
    type: [
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
    ],
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
