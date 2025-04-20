defmodule PowerOfThree do
  @moduledoc """
  generate cube.dev config files for cubes defined inline with Ecto.Schema
  """

  defmacro __using__(_) do
    quote do
      import PowerOfThree, only: [cube: 3, dimension: 2, measure: 2, time_dimensions: 1]
      Module.register_attribute(__MODULE__, :primary_keys, accumulate: true)
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
        Module.register_attribute(__MODULE__, :primary_keys, accumulate: true)
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
        cube_primary_keys = @cube_primary_keys |> Enum.reverse()
        measures = @measures |> Enum.reverse()
        dimensions = @dimensions |> Enum.reverse()
        datetime_dimensions = @datetime_dimensions |> Enum.reverse()

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
      Module.put_attribute(__MODULE__, :time_dimensions, {:inserted_at, :time})

      PowerOfThree.__dimension__(__MODULE__, :inserted_at, :time,
        description: " Default to inserted_at"
      )
    end
  end

  defmacro dimension(dimension_name, for: ecto_schema_field) do
    # TODO use an_ecto_schema_field to derive data type of ecto field
    quote bind_quoted: binding() do
      # TODO derive type knowing ecto_schema_field name
      if Keyword.get(Module.get_attribute(__MODULE__, :ecto_fields), ecto_schema_field, false) do
        raise ArgumentError,
              "Dimensions can only created for existing ecto schema field!\n" <>
                "Dimensions `for:` is  #{inspect(ecto_schema_field)} , Ecto schema has this fields declared: \n #{inspect(Module.get_attribute(__MODULE__, :ecto_fields))}"
      end

      PowerOfThree.__dimension__(__MODULE__, dimension_name, :string,
        ecto_schema_field: ecto_schema_field
      )
    end
  end

  defmacro dimension(dimension_name,
             for: list_of_ecto_schema_fields,
             sql: native_sql_using_list_of_ecto_schema_fields
           )
           when is_list(list_of_ecto_schema_fields) do
    quote bind_quoted: binding() do
      # TODO use an_ecto_schema_field to derive data type of ecto field
      # TODO use the `list_of_ecto_schema_fields` to validate `native_sql_using_fields_list`
      PowerOfThree.__dimension__(__MODULE__, dimension_name, :string,
        sql: native_sql_using_list_of_ecto_schema_fields,
        ecto_schema_fields: list_of_ecto_schema_fields
      )
    end
  end

  defmacro measure(measure_name,
             for: a_field,
             type: measure_type
           ) do
    IO.inspect(__CALLER__)
    IO.inspect(measure_name)
    IO.inspect(a_field)
    IO.inspect(measure_type)
    # schema(__CALLER__, source, true, :id, block)
  end

  @doc false
  def __dimension__(module, time_dimension_name, type, opts \\ [])

  def __dimension__(module, time_dimension_name, :time, opts) do
    # TODO add to time_dimensions[]?
    PowerOfThree.Dimension.define_dimension(module, time_dimension_name, :time, opts)
  end

  def __dimension__(module, dimension_name, :string, opts) do
    # TODO some implement defence!
    PowerOfThree.Dimension.define_dimension(module, dimension_name, :string, opts)
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
