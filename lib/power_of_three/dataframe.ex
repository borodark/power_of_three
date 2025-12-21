defmodule PowerOfThree.CubeFrame do
  @moduledoc """
  Explorer DataFrame integration for query results.

  This module provides conditional compilation support for Explorer.
  If Explorer is available at compile time, results can be converted
  to DataFrames. Otherwise, results are returned as maps.

  ## Explorer Integration

  Add Explorer to your dependencies:

      {:explorer, "~> 0.11.1"}

  Then query results will automatically be returned as DataFrame:

      df = Customer.df(columns: [Customer.dimensions().brand(), Customer.measures().count()])
      # => %Explorer.DataFrame{...}
  """

  @doc """
  Converts query result to Explorer.DataFrame or Explorer.Series.

  ## Examples

      result_map = %{"col1" => [1, 2, 3], "col2" => ["a", "b", "c"]}
      CubeFrame.from_result(result_map)
      # => %Explorer.DataFrame{...}
  """
  @spec from_result(map()) :: Explorer.DataFrame.t() | Explorer.Series.t()
  def from_result(result_map) when is_map(result_map) do
    case Map.keys(result_map) |> Enum.count() do
      0 ->
        result_map |> IO.inspect(label: :"%{}_AxyeTb!!!!!!")
        Explorer.Series.from_list([]) |> IO.inspect(label: :EMPTY_NULL_SERIES)

      1 ->
        [col] = Map.keys(result_map)
        Explorer.Series.from_list(result_map[col]) |> IO.inspect(label: :SERIES)

      _ ->
        # TODO count: to Explorer.DataFrame.mutate(df, "*any*" <>count: b + 1)

        Explorer.DataFrame.new(result_map) |> IO.inspect(label: :DataFrame)
    end
  end

  def from_result(%{}), do: Explorer.Series.from_list([])

  def result_type, do: :dataframe
end
