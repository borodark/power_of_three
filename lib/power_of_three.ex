defmodule PowerOfThree do
  @moduledoc """
  generate cube.dev config files for cubes defined inline with Ecto.Schema
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

        @cube_defined unquote(caller.line)

        # @after_compile PowerOfThree

        # TODO add these to __meta__ functions for reflection
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
      # TODO process users time dimensions: loop
      Module.put_attribute(__MODULE__, :datetime_dimensions, {:inserted_at, :time})

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

        {ecto_field_type, ecto_field_option} ->
          Module.put_attribute(
            __MODULE__,
            :dimensions,
            {dimension_name, ecto_field_type, description}
          )

          PowerOfThree.__dimension__(__MODULE__, dimension_name, ecto_field_type,
            ecto_field: ecto_schema_field
          )
      end
    end
  end

  defmacro dimension(dimension_name,
             # TODO
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
          raise ArgumentError,
                "Cube Dimensions are `for:` *existing* ecto schema field!\n" <>
                  "The ecto field names are: #{inspect(list_of_ecto_schema_fields)},\n Not all found in the declared ecto fields: \n #{inspect(Keyword.keys(Module.get_attribute(__MODULE__, :ecto_fields)))}"

        true ->
          Module.put_attribute(
            __MODULE__,
            :dimensions,
            {dimension_name, native_sql_return_type, description}
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
    PowerOfThree.Dimension.define_dimension(module, dimension_name,
      cube_primary_keys: list_of_fields_of_composite_key
    )
  end

  def __dimension__(module, time_dimension_name, type, opts \\ [])

  def __dimension__(module, time_dimension_name, :time, opts) do
    PowerOfThree.Dimension.define_dimension(module, time_dimension_name, :time, opts)
  end

  def __dimension__(module, dimension_name, :string, opts) do
    PowerOfThree.Dimension.define_dimension(module, dimension_name, :string, opts)
  end

  def __dimension__(module, dimension_name, native_sql_return_type,
        sql: native_sql_using_list_of_ecto_schema_fields,
        ecto_fields: list_of_ecto_schema_fields
      ) do
    PowerOfThree.Dimension.define_dimension(module, dimension_name, native_sql_return_type,
      sql: native_sql_using_list_of_ecto_schema_fields,
      ecto_fields: list_of_ecto_schema_fields
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

defmodule PowerOfThree.Dimension do
  @moduledoc """
  https://cube.dev/docs/reference/data-model/dimensions
  A Dimension of Cube object with following properties:
  """

  @properties_in_opts [
    :case,
    :description,
    :format,
    :meta,
    :primary_key,
    :propagate_filters_to_sub_query,
    :public,
    :sql,
    :sub_query,
    :title,
    :type,
    :granularities
  ]
  @dimension_types [:string, :time, :number, :boolean, :geo]
  @dimension_formats [:imageUrl, :id, :link, :currency, :percent]

  def define_dimension(mod, name, valid_type, opts) when valid_type in @dimension_types do
    "CALLING POWEROFTHREE.DIMENSION.DEFINE_DIMENSION" |> IO.inspect()
    [mod, name, valid_type, opts] |> Enum.map(&IO.inspect/1)
  end

  def define_dimension(mod, name, cube_primary_keys: list_of_fields_of_composite_key) do
    "CALLING POWEROFTHREE.DIMENSION.DEFINE_DIMENSION" |> IO.inspect()
    [mod, name, list_of_fields_of_composite_key] |> Enum.map(&IO.inspect/1)
  end
end

defmodule PowerOfThree.Measure do
  @moduledoc """
  https://cube.dev/docs/reference/data-model/measures
  A Measure of Cube object with following:
  """

  @type t() :: %__MODULE__{
          name: String.t() | nil,
          description: String.t() | nil,
          drill_members: list(),
          filters: list(),
          format: atom() | nil,
          meta: String.t() | nil,
          rolling_window: atom() | nil,
          public: boolean(),
          sql: String.t() | nil,
          title: String.t() | nil,
          type: atom()
        }

  defstruct name: nil,
            description: nil,
            drill_members: [],
            filters: [],
            format: nil,
            meta: "X is Cubifed",
            rolling_window: nil,
            public: true,
            sql: nil,
            title: nil,
            type: :count

  @types [
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

  @formats [:percent, :currency]

  # These parameters have a format defined as (-?\d+) (minute|hour|day|week|month|year)

  @rolling_window [:trailing, :leading]
end
