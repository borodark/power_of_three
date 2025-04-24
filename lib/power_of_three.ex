defmodule PowerOfThree do
  @moduledoc """

  Able to generate cube.dev config files for cubes defined for one `using Ecto.Schema`.
  The dimensions and measures derive some defaults
  from `Ecto.Schema.field` properties mentioned in the defenition

  Cube dimension types    | Ecto type               | Elixir type
  :---------------------- | :---------------------- | :---------------------
  number                  | `:id`                   | `integer`
  string                  | `:binary_id`            | `binary`
  number, boolean         | `:integer`              | `integer`
  number, boolean enough? | `:float`                | `float`
  `:boolean`              | `boolean`               | boolean
  `:string`               | UTF-8 encoded `string`  |  string
  `:binary`               | `binary`                |  string
  `:bitstring`            | `bitstring`             |  string
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
      import PowerOfThree, only: [cube: 3, dimension: 2, measure: 2, time_dimensions: 1]
      Module.register_attribute(__MODULE__, :cube_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :measures, accumulate: true)
      Module.register_attribute(__MODULE__, :dimensions, accumulate: true)
      Module.register_attribute(__MODULE__, :time_dimensions, accumulate: true)
      Module.put_attribute(__MODULE__, :cube_enabled, true)
    end
  end

  defmacro cube(cube_name, [of: what_ecto_schema], do: block) do
    cube(__CALLER__, cube_name, what_ecto_schema, block)
  end

  defp cube(caller, cube_name, what_ecto_schema, block) do
    prelude =
      quote do
        if line = Module.get_attribute(__MODULE__, :cube_defined) do
          raise "cube already defined for #{inspect(__MODULE__)} on line #{line}"
        end

        case Module.get_attribute(__MODULE__, :ecto_fields, false) do
          [id: _tuple_of_id_always] ->
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

        cube_name = unquote(cube_name) |> IO.inspect(label: :cube_name)
        what_ecto_schema = unquote(what_ecto_schema) |> IO.inspect(label: :what_ecto_schema)

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
          @cube_primary_keys |> Enum.reverse() |> IO.inspect(label: :cube_primary_keys)

        measures = @measures |> Enum.reverse() |> IO.inspect(label: :measures)
        dimensions = @dimensions |> Enum.reverse() |> IO.inspect(label: :dimensions)

        datetime_dimensions =
          @datetime_dimensions |> Enum.reverse() |> IO.inspect(label: :datetime_dimensions)

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

      PowerOfThree.__dimension__(__MODULE__, :inserted_at, :time,
        description: " Default to inserted_at"
      )
    end
  end

  defmacro dimension(dimension_name, description: description, for: ecto_schema_field) do
    quote bind_quoted: binding() do
      case Keyword.get(Module.get_attribute(__MODULE__, :ecto_fields), ecto_schema_field, false) do
        false ->
          raise ArgumentError,
                "Cube Dimension wants field #{inspect(ecto_schema_field)}, but Ecto schema has only these: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        {original_ecto_field_type, _always} ->
          # TODO resolve Ecto Datetimes to :time
          dimension_type =
            case original_ecto_field_type in [
                   :date,
                   :time,
                   :time_usec,
                   :naive_datetime,
                   :naive_datetime_usec,
                   :utc_datetime,
                   :utc_datetime_usec
                 ] do
              # cube use onlu time
              true ->
                :time

              false ->
                original_ecto_field_type
            end

          Module.put_attribute(
            __MODULE__,
            :dimensions,
            {dimension_name, dimension_type,
             [
               ecto_field_type: original_ecto_field_type,
               ecto_field: ecto_schema_field,
               description: description
             ]}
          )

          PowerOfThree.__dimension__(__MODULE__, dimension_name, dimension_type,
            ecto_field_type: original_ecto_field_type,
            ecto_field: ecto_schema_field,
            description: description
          )
      end
    end
  end

  defmacro dimension(dimension_name,
             description: description,
             for: composit_key_fields,
             cube_primary_key: true
           ) do
    quote bind_quoted: binding() do
      intersection =
        for ecto_field <- Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)),
            ecto_field in composit_key_fields,
            do: ecto_field

      case composit_key_fields |> Enum.sort() == intersection |> Enum.sort() do
        false ->
          raise ArgumentError,
                "Cube Primary Key Dimension wants all of: #{inspect(composit_key_fields)}\n" <>
                  "But only these are avalable: #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        true ->
          Module.put_attribute(__MODULE__, :cube_primary_keys, composit_key_fields)

          PowerOfThree.__dimension__(__MODULE__, dimension_name,
            description: description,
            for: composit_key_fields,
            cube_primary_key: true
          )
      end
    end
  end

  defmacro dimension(dimension_name,
             description: description,
             type: native_sql_return_type,
             for: list_of_ecto_schema_fields,
             sql: native_sql_using_list_of_ecto_schema_fields
           )
           when is_list(list_of_ecto_schema_fields) do
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
          Module.put_attribute(
            __MODULE__,
            :dimensions,
            {dimension_name, native_sql_return_type,
             sql: native_sql_using_list_of_ecto_schema_fields,
             ecto_fields: list_of_ecto_schema_fields,
             description: description}
          )

          # TODO push description here too
          PowerOfThree.__dimension__(__MODULE__, dimension_name, native_sql_return_type,
            sql: native_sql_using_list_of_ecto_schema_fields,
            ecto_fields: list_of_ecto_schema_fields
          )
      end
    end
  end

  @doc false
  def __dimension__(module, dimension_name,
        description: _description,
        for: list_of_fields_of_composite_key,
        cube_primary_key: true
      ) do
    PowerOfThree.Dimension.define(module, dimension_name,
      cube_primary_keys: list_of_fields_of_composite_key
    )
  end

  def __dimension__(module, time_dimension_name, type, opts \\ [])

  def __dimension__(module, time_dimension_name, one_of_ecto_date_times, opts)
      when one_of_ecto_date_times in [
             :date,
             :time,
             :time_usec,
             :naive_datetime,
             :naive_datetime_usec,
             :utc_datetime,
             :utc_datetime_usec
           ] do
    Module.put_attribute(module, :datetime_dimensions, {time_dimension_name, :time, opts})
    PowerOfThree.Dimension.define(module, time_dimension_name, :time, opts)
  end

  def __dimension__(module, dimension_name, :string, opts) do
    PowerOfThree.Dimension.define(module, dimension_name, :string, opts)
  end

  def __dimension__(module, dimension_name, native_sql_return_type,
        sql: native_sql_using_list_of_ecto_schema_fields,
        ecto_fields: list_of_ecto_schema_fields
      ) do
    PowerOfThree.Dimension.define(module, dimension_name, native_sql_return_type,
      sql: native_sql_using_list_of_ecto_schema_fields,
      ecto_fields: list_of_ecto_schema_fields
    )
  end

  # TODO perhaps resolve ecto_type into measure_type? 

  defmacro measure(measure_name,
             type: measure_type,
             for: for_ecto_fields,
             description: description
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
          Module.put_attribute(
            __MODULE__,
            :measures,
            {measure_name, measure_type, [description: description, ecto_fields: for_ecto_fields]}
          )

          PowerOfThree.__measure__(
            __MODULE__,
            measure_name,
            type: measure_type,
            description: description,
            ecto_fields: for_ecto_fields
          )
      end
    end
  end

  defmacro measure(measure_name,
             type: measure_type,
             for: for_ecto_field,
             description: description
           ) do
    quote bind_quoted: binding() do
      case Keyword.get(Module.get_attribute(__MODULE__, :ecto_fields), for_ecto_field, false) do
        false ->
          raise ArgumentError,
                "Cube Measure wants: \n#{inspect(for_ecto_field)},\n but only those found: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        {ecto_type, _ecto_always} ->
          Module.put_attribute(
            __MODULE__,
            :measures,
            {measure_name, measure_type,
             [description: description, ecto_fields: {for_ecto_field, ecto_type}]}
          )

          PowerOfThree.__measure__(
            __MODULE__,
            measure_name,
            type: measure_type,
            description: description,
            ecto_fields: {for_ecto_field, ecto_type}
          )
      end
    end
  end

  defmacro measure(measure_name,
             type: :time,
             sql: sql_returning_datetime_value,
             for: for_ecto_field,
             description: description
           ) do
    quote bind_quoted: binding() do
      case Keyword.get(Module.get_attribute(__MODULE__, :ecto_fields), for_ecto_field, false) do
        false ->
          raise ArgumentError,
                "Cube Measure wants: \n#{inspect(for_ecto_field)},\n but only those found: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        {ecto_type, _ecto_always} ->
          # TODO resolve 
          Module.put_attribute(
            __MODULE__,
            :measures,
            {measure_name, measure_type,
             [description: description, ecto_fields: {for_ecto_field, ecto_type}]}
          )

          PowerOfThree.__measure__(
            __MODULE__,
            measure_name,
            type: measure_type,
            description: description,
            ecto_fields: {for_ecto_field, ecto_type}
          )
      end
    end
  end

  @doc false
  def __measure__(module, name,
        type: measure_type,
        description: description,
        ecto_fields: list_of_ecto_schema_fields
      ) do
    PowerOfThree.Measure.define(module, name, measure_type,
      ecto_fields: list_of_ecto_schema_fields,
      description: description
    )
  end
end

defmodule PowerOfThree.Cube do
  @moduledoc """
  https://cube.dev/docs/reference/data-model/cube
  Top of Cube object with following:
  TODO Supported cron formats
  """

  @properties_in_opts [
    :name,
    :sql_alias,
    :extends,
    :data_source,
    :sql,
    :sql_table,
    :title,
    :description,
    :public,
    :refresh_key,
    :meta,
    :pre_aggregations,
    :joins,
    :dimensions,
    :hierarchies,
    :segments,
    :measures,
    :access_policy
  ]
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
