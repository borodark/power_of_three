defmodule PowerOfThree do
  @doc false
  defmacro __using__(_) do
    quote do
      import PowerOfThree, only: [cube: 3, dimension: 3, dimension: 2, measure: 3, measure: 2]

      Module.register_attribute(__MODULE__, :cube_primary_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :cube_measures, accumulate: true)
      Module.register_attribute(__MODULE__, :cube_dimensions, accumulate: true)
      Module.put_attribute(__MODULE__, :cube_enabled, true)
    end
  end

  defmacro cube(cube_name, [of: what_ecto_schema], do: block) do
    IO.inspect(cube_name)
    IO.inspect(what_ecto_schema)
    IO.inspect(block)
  end

  defmacro dimension(dimension_name, for: a_field) do
    IO.inspect(__CALLER__)
    IO.inspect(dimension_name)
    IO.inspect(a_field)
  end

  defmacro dimension(dimension_name, for: fields_list, sql: native_sql_using_fields_list) do
    IO.inspect(__CALLER__)
    IO.inspect(dimension_name)
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
end

defmodule PowerOfThree.Cube do
  """
  https://cube.dev/docs/reference/data-model/cube
  Top of Cube object with following:
  - name
  - sql_alias
  - extends
  - data_source
  - sql
  - sql_table
  - title
  - description
  - public
  - refresh_key
  - Supported cron formats
  - meta
  - pre_aggregations
  - joins
  - dimensions
  - hierarchies
  - segments
  - measures
  - access_policy
  """
end

defmodule PowerOfThree.Dimension do
  """
  https://cube.dev/docs/reference/data-model/dimensions
  A Dimension of Cube object with following:
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
end

defmodule PowerOfThree.Measure do
  """
  https://cube.dev/docs/reference/data-model/measures
  A Dimension of Cube object with following:
  - name
  - description
  - drill_members
  - filters
  - format
  - meta
  - rolling_window
  - public
  - sql
  - title
  - type
  """

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
end
