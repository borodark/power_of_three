defmodule PowerOfThree do
  @moduledoc """

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
        only: [cube: 3, dimension: 3, measure: 3, measure: 2, time_dimensions: 1]

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
    :sql_alias,
    # TODO? :extends,
    :data_source,
    :sql,
    :sql_table,
    :title,
    :description,
    :public,
    :refresh_key,
    :meta
    # :pre_aggregations,
    # :joins,
    # :dimensions,
    # :hierarchies,
    # :segments,
    # :measures,
    # :access_policy
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

        # |> Enum.into(%{})
        measures = @measures |> Enum.reverse()

        # |> Enum.into(%{})
        # |> Enum.reverse()
        dimensions =
          @dimensions

        a_cube_config = [
          %{name: cube_name}
          |> Map.merge(cube_opts)
          |> Map.merge(%{dimensions: dimensions, measures: measures})
        ]

        File.write(
          "/tmp/cubes.yaml",
          %{cubes: a_cube_config}
          |> Ymlr.document!()
        )

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
        :datetime_dimensions,
        {:inserted_at, :time, [description: " Default to inserted_at"]}
      )
    end
  end

  defmacro dimension(dimension_name, one_or_a_list_of_ecto_schema_fields, opts \\ [])

  defmacro dimension(
             dimension_name,
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
          sql = opts[:sql] || list_of_ecto_schema_fields |> Enum.join("||")
          desc = opts[:description] || "Documentation if Empathy"
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

  defmacro dimension(dimension_name, ecto_schema_field, opts) do
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
              end

          # TODO enforce CUBE.DEV grammar
          # our_opts = take_our_opts()
          sql = opts[:sql] || ecto_schema_field
          desc = opts[:description] || "Documentation if Empathy"

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
              description: desc
              # meta: %{ecto_field: for_ecto_field, ecto_type: ecto_type}
            }
          )
      end
    end
  end

  defmodule PowerOfThree.Dimension.Case do
    @type t() :: %__MODULE__{}
    defstruct when: [],
              else: nil
  end

  defmodule PowerOfThree.Dimension do
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
    @dimension_type [:string, :time, :number, :boolean, :geo]
    @format [:imageUrl, :id, :link, :currency, :percent]

    alias PowerOfThree.Dimension.Case

    @type t() :: %__MODULE__{
            name: String.t() | nil,
            case: Case.t() | nil,
            description: String.t() | nil,
            format: atom() | nil,
            meta: Keyword.t(),
            public: boolean(),
            sql: String.t() | nil,
            title: String.t() | nil,
            type: atom()
            # TODO granularities: https://cube.dev/docs/reference/data-model/dimensions#granularities 
          }

    defstruct name: nil,
              case: nil,
              description: nil,
              format: nil,
              meta: [tag: :dimension],
              public: true,
              sql: nil,
              title: nil,
              type: :string

    # TODO granularities: https://cube.dev/docs/reference/data-model/dimensions#granularities 

    def define(mod, name, valid_type, opts) when valid_type in @dimension_type do
      # |> Enum.map(&IO.inspect/1)
      [mod, name, valid_type, opts]
    end

    def define(mod, name, cube_primary_keys: list_of_fields_of_composite_key) do
      #  |> Enum.map(&IO.inspect/1)
      [mod, name, list_of_fields_of_composite_key]
    end
  end

  defmodule PowerOfThree.Measure do
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
    # These parameters have a format defined as (-?\d+) (minute|hour|day|week|month|year)
    @rolling_window [:trailing, :leading]

    def define(mod, name, valid_type, opts) when valid_type in @measure_types do
      # |> Enum.map(&IO.inspect/1)
      [mod, name, valid_type, opts]
    end

    @type t() :: %__MODULE__{
            name: String.t() | nil,
            sql: String.t() | nil,
            type: atom(),
            description: String.t() | nil,
            drill_members: list(),
            filters: list(),
            format: atom() | nil,
            meta: Keyword.t(),
            rolling_window: atom() | nil,
            public: boolean(),
            title: String.t() | nil
          }

    @mandatory [:name, :sql, :type]
    defstruct name: nil,
              sql: nil,
              type: :count,
              title: nil,
              description: nil,
              drill_members: [],
              filters: [],
              format: nil,
              meta: [tag: :measure],
              rolling_window: nil,
              public: true
  end
end
