defmodule PowerOfThree.FilterCondition do
  @moduledoc """
  Represents a typed WHERE clause condition using DimensionRef or MeasureRef.

  ## Supported Operators

  - `:==` - Equals
  - `:!=` - Not equals
  - `:>` - Greater than
  - `:<` - Less than
  - `:>=` - Greater than or equal
  - `:<=` - Less than or equal
  - `:in` - In list
  - `:not_in` - Not in list
  - `:like` - SQL LIKE pattern
  - `:not_like` - SQL NOT LIKE pattern
  - `:is_nil` - Is NULL
  - `:is_not_nil` - Is NOT NULL

  ## Examples

      # Simple equality
      {Customer.Dimensions.brand(), :==, "BQ"}

      # Greater than
      {Customer.Measures.count(), :>, 1000}

      # IN operator
      {Customer.Dimensions.market(), :in, ["US", "CA", "MX"]}

      # NULL check (value is ignored)
      {Customer.Dimensions.email(), :is_nil, nil}

  ## Conversion

  FilterConditions can be converted to:
  - Cube REST API filter format (for HTTP queries)
  - SQL WHERE clause (for ADBC queries)
  """

  alias PowerOfThree.{DimensionRef, MeasureRef}

  @type column_ref :: DimensionRef.t() | MeasureRef.t()
  @type operator ::
          :==
          | :!=
          | :>
          | :<
          | :>=
          | :<=
          | :in
          | :not_in
          | :like
          | :not_like
          | :is_nil
          | :is_not_nil
  @type value :: term()
  @type t :: {column_ref(), operator(), value()}

  @supported_operators [
    :==,
    :!=,
    :>,
    :<,
    :>=,
    :<=,
    :in,
    :not_in,
    :like,
    :not_like,
    :is_nil,
    :is_not_nil
  ]

  @doc """
  Validates a filter condition.

  ## Examples

      iex> FilterCondition.validate({Customer.Dimensions.brand(), :==, "BQ"})
      :ok

      iex> FilterCondition.validate({Customer.Dimensions.brand(), :invalid, "BQ"})
      {:error, "Unsupported operator: :invalid"}
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate({column_ref, operator, _value}) do
    with :ok <- validate_column_ref(column_ref),
         :ok <- validate_operator(operator) do
      :ok
    end
  end

  def validate(_),
    do: {:error, "Filter condition must be a 3-tuple: {column_ref, operator, value}"}

  defp validate_column_ref(%DimensionRef{}), do: :ok
  defp validate_column_ref(%MeasureRef{}), do: :ok
  defp validate_column_ref(_), do: {:error, "First element must be a DimensionRef or MeasureRef"}

  defp validate_operator(op) when op in @supported_operators, do: :ok
  defp validate_operator(op), do: {:error, "Unsupported operator: #{inspect(op)}"}

  @doc """
  Converts a filter condition to Cube REST API filter format.

  ## Examples

      iex> condition = {Customer.Dimensions.brand(), :==, "BQ"}
      iex> FilterCondition.to_cube_filter(condition)
      {:ok, %{"member" => "power_customers.brand", "operator" => "equals", "values" => ["BQ"]}}
  """
  @spec to_cube_filter(t()) :: {:ok, map()} | {:error, String.t()}
  def to_cube_filter({column_ref, operator, value}) do
    with :ok <- validate({column_ref, operator, value}),
         {:ok, member} <- get_member_name(column_ref),
         {:ok, cube_operator} <- operator_to_cube(operator),
         {:ok, values} <- value_to_cube_values(operator, value) do
      filter = %{
        "member" => member,
        "operator" => cube_operator,
        "values" => values
      }

      {:ok, filter}
    end
  end

  @doc """
  Converts a filter condition to SQL WHERE clause fragment.

  ## Examples

      iex> condition = {Customer.Dimensions.brand(), :==, "BQ"}
      iex> FilterCondition.to_sql(condition)
      {:ok, "brand = 'BQ'"}
  """
  @spec to_sql(t()) :: {:ok, String.t()} | {:error, String.t()}
  def to_sql({column_ref, operator, value}) do
    with :ok <- validate({column_ref, operator, value}),
         {:ok, column_name} <- get_column_name(column_ref),
         {:ok, sql_fragment} <- build_sql_fragment(column_name, operator, value) do
      {:ok, sql_fragment}
    end
  end

  # Get member name for Cube REST API (e.g., "power_customers.brand")
  defp get_member_name(%DimensionRef{name: name, module: module}) do
    cube_name = extract_cube_name(module)
    {:ok, "#{cube_name}.#{name}"}
  end

  defp get_member_name(%MeasureRef{name: name, module: module}) do
    cube_name = extract_cube_name(module)
    {:ok, "#{cube_name}.#{name}"}
  end

  # Get column name for SQL (e.g., "brand")
  defp get_column_name(%DimensionRef{name: name}), do: {:ok, to_string(name)}
  defp get_column_name(%MeasureRef{name: name}), do: {:ok, to_string(name)}

  # Extract cube name from module
  defp extract_cube_name(module) do
    module.__info__(:attributes)[:cube_config]
    |> List.first()
    |> Map.get(:name)
    |> to_string()
  end

  # Convert PowerOfThree operator to Cube REST API operator
  defp operator_to_cube(:==), do: {:ok, "equals"}
  defp operator_to_cube(:!=), do: {:ok, "notEquals"}
  defp operator_to_cube(:>), do: {:ok, "gt"}
  defp operator_to_cube(:<), do: {:ok, "lt"}
  defp operator_to_cube(:>=), do: {:ok, "gte"}
  defp operator_to_cube(:<=), do: {:ok, "lte"}
  # Cube uses "equals" with array
  defp operator_to_cube(:in), do: {:ok, "equals"}
  defp operator_to_cube(:not_in), do: {:ok, "notEquals"}
  defp operator_to_cube(:like), do: {:ok, "contains"}
  defp operator_to_cube(:not_like), do: {:ok, "notContains"}
  defp operator_to_cube(:is_nil), do: {:ok, "notSet"}
  defp operator_to_cube(:is_not_nil), do: {:ok, "set"}

  # Convert value to Cube REST API values array
  defp value_to_cube_values(:is_nil, _), do: {:ok, []}
  defp value_to_cube_values(:is_not_nil, _), do: {:ok, []}
  defp value_to_cube_values(:in, values) when is_list(values), do: {:ok, values}
  defp value_to_cube_values(:not_in, values) when is_list(values), do: {:ok, values}
  defp value_to_cube_values(_, value), do: {:ok, [value]}

  # Build SQL WHERE clause fragment
  defp build_sql_fragment(column, :==, value), do: {:ok, "#{column} = #{sql_value(value)}"}
  defp build_sql_fragment(column, :!=, value), do: {:ok, "#{column} != #{sql_value(value)}"}
  defp build_sql_fragment(column, :>, value), do: {:ok, "#{column} > #{sql_value(value)}"}
  defp build_sql_fragment(column, :<, value), do: {:ok, "#{column} < #{sql_value(value)}"}
  defp build_sql_fragment(column, :>=, value), do: {:ok, "#{column} >= #{sql_value(value)}"}
  defp build_sql_fragment(column, :<=, value), do: {:ok, "#{column} <= #{sql_value(value)}"}

  defp build_sql_fragment(column, :in, values) when is_list(values) do
    values_str = values |> Enum.map(&sql_value/1) |> Enum.join(", ")
    {:ok, "#{column} IN (#{values_str})"}
  end

  defp build_sql_fragment(column, :not_in, values) when is_list(values) do
    values_str = values |> Enum.map(&sql_value/1) |> Enum.join(", ")
    {:ok, "#{column} NOT IN (#{values_str})"}
  end

  defp build_sql_fragment(column, :like, pattern),
    do: {:ok, "#{column} LIKE #{sql_value(pattern)}"}

  defp build_sql_fragment(column, :not_like, pattern),
    do: {:ok, "#{column} NOT LIKE #{sql_value(pattern)}"}

  defp build_sql_fragment(column, :is_nil, _), do: {:ok, "#{column} IS NULL"}
  defp build_sql_fragment(column, :is_not_nil, _), do: {:ok, "#{column} IS NOT NULL"}

  # Format value for SQL
  defp sql_value(value) when is_binary(value), do: "'#{String.replace(value, "'", "''")}'"
  defp sql_value(value) when is_number(value), do: to_string(value)
  defp sql_value(value) when is_boolean(value), do: if(value, do: "TRUE", else: "FALSE")
  defp sql_value(nil), do: "NULL"
  defp sql_value(value), do: "'#{value}'"
end
