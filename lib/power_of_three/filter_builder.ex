defmodule PowerOfThree.FilterBuilder do
  @moduledoc """
  Builds WHERE clauses from typed filter conditions.

  Uses DimensionRef and MeasureRef for compile-time type safety and SQL injection prevention.

  ## Syntax

      where: [
        {Customer.Dimensions.brand(), :==, "BQ"},
        {Customer.Measures.count(), :>, 1000}
      ]

  All conditions in the list are combined with AND logic.
  """

  alias PowerOfThree.FilterCondition

  @type where_clause :: nil | [FilterCondition.t()]

  @doc """
  Converts WHERE clause to Cube REST API filters format.

  ## Examples

      iex> where = [{Customer.Dimensions.brand(), :==, "BQ"}]
      iex> FilterBuilder.to_cube_filters(where)
      {:ok, [%{"member" => "power_customers.brand", "operator" => "equals", "values" => ["BQ"]}]}
  """
  @spec to_cube_filters(where_clause()) :: {:ok, [map()]} | {:error, String.t()}
  def to_cube_filters(nil), do: {:ok, []}
  def to_cube_filters([]), do: {:ok, []}

  def to_cube_filters(conditions) when is_list(conditions) do
    conditions
    |> Enum.reduce_while({:ok, []}, fn condition, {:ok, acc} ->
      case FilterCondition.to_cube_filter(condition) do
        {:ok, filter} -> {:cont, {:ok, [filter | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, filters} -> {:ok, Enum.reverse(filters)}
      error -> error
    end
  end

  @doc """
  Converts WHERE clause to SQL WHERE fragment.

  ## Examples

      iex> where = [{Customer.Dimensions.brand(), :==, "BQ"}, {Customer.Measures.count(), :>, 1000}]
      iex> FilterBuilder.to_sql(where)
      {:ok, "brand = 'BQ' AND count > 1000"}
  """
  @spec to_sql(where_clause()) :: {:ok, String.t()} | {:error, String.t()}
  def to_sql(nil), do: {:ok, ""}
  def to_sql([]), do: {:ok, ""}

  def to_sql(conditions) when is_list(conditions) do
    conditions
    |> Enum.reduce_while({:ok, []}, fn condition, {:ok, acc} ->
      case FilterCondition.to_sql(condition) do
        {:ok, sql_fragment} -> {:cont, {:ok, [sql_fragment | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, fragments} -> {:ok, fragments |> Enum.reverse() |> Enum.join(" AND ")}
      error -> error
    end
  end

  @doc """
  Validates a WHERE clause.

  ## Examples

      iex> FilterBuilder.validate([{Customer.Dimensions.brand(), :==, "BQ"}])
      :ok

      iex> FilterBuilder.validate([{:invalid, :==, "BQ"}])
      {:error, "First element must be a DimensionRef or MeasureRef"}
  """
  @spec validate(where_clause()) :: :ok | {:error, String.t()}
  def validate(nil), do: :ok
  def validate([]), do: :ok

  def validate(conditions) when is_list(conditions) do
    Enum.reduce_while(conditions, :ok, fn condition, :ok ->
      case FilterCondition.validate(condition) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def validate(_), do: {:error, "WHERE clause must be a list of filter conditions"}
end
