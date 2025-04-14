defmodule PowerOfThree do
  @moduledoc """
  generate cube.dev config files for cubes defined inline with Ecto.Schema
  """
  @doc false
  defmacro __using__(_) do
    quote do
      import PowerOfThree, only: [cube: 3, dimension: 2, measure: 2]

      Module.register_attribute(__MODULE__, :cube_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :cube_measures, accumulate: true)
      Module.register_attribute(__MODULE__, :cube_dimensions, accumulate: true)
      Module.register_attribute(__MODULE__, :cube_time_dimensions, accumulate: true)
      Module.put_attribute(__MODULE__, :cube_enabled, true)
    end
  end

  defmacro cube(cube_name, [of: what_ecto_schema], do: block) do
    IO.inspect(cube_name)
    IO.inspect(what_ecto_schema)
    IO.inspect(block)

    quote do
      Module.put_attribute(__MODULE__, :cube_name, unquote(cube_name))
      Module.put_attribute(__MODULE__, :cube_table, unquote(what_ecto_schema))
    end
  end

  defmacro dimension(dimension_name, for: a_field) do
    IO.inspect(__CALLER__)
    IO.inspect(dimension_name)
    IO.inspect(a_field)
  end

  defmacro dimension(dimension_name, for: fields_list, sql: native_sql_using_fields_list) do
    IO.inspect(__CALLER__)
    dimension_name |> IO.inspect(label: :dimension_name)
    IO.inspect(fields_list)
    IO.inspect(native_sql_using_fields_list)
    # schema(__CALLER__, source, true, :id, block)
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

  @doc """
  Uses `:inserted_at` as default time dimension
  """
  defmacro time_dimensions(fields_of_datetime_type \\ [:inserted_at]) do
    quote bind_quoted: binding() do
      __define_time_dimensions__(__MODULE__, fields_of_datetime_type)
    end
  end

  @doc false
  def __define_time_dimensions__(mod, time_dimensions \\ [:inserted_at]) do
    IO.inspect(time_dimensions)
    # TODO implement other then default
    __dimension__(mod, :inserted_at, :time, description: " Default to inserted_at")
    :ok
  end

  @doc false
  def __dimension__(mod, name, type, opts) do
    # TODO implement defence!
    PowerOfThree.Dimension.define_dimension(mod, name, type, opts)
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
    [mod, name, valid_type, opts] |> Enum.map(&IO.inspect/1)
  end
end

defmodule PowerOfThree.Measure do
  @moduledoc """
  https://cube.dev/docs/reference/data-model/measures
  A Measure of Cube object with following:
  """

  @properties [
    :name,
    :description,
    :drill_members,
    :filters,
    :format,
    :meta,
    :rolling_window,
    :public,
    :sql,
    :title,
    :type
  ]

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

  @measure_formats [:percent, :currency]
end
