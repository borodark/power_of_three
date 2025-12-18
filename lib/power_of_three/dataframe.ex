defmodule PowerOfThree.DataFrame do
  @moduledoc """
  Optional Explorer DataFrame integration for query results.

  This module provides conditional compilation support for Explorer.
  If Explorer is available at compile time, results can be converted
  to DataFrames. Otherwise, results are returned as maps.

  ## Explorer Integration

  Add Explorer to your dependencies:

      {:explorer, "~> 0.8"}

  Then query results will automatically be returned as DataFrames:

      # With Explorer available
      df = Customer.df(columns: [Customer.dimensions().brand(), Customer.measures().count()])
      # => %Explorer.DataFrame{...}

      # Without Explorer
      df = Customer.df(columns: [...])
      # => %{"brand" => [...], "measure(customer.count)" => [...]}
  """

  @compile {:no_warn_undefined, Explorer.DataFrame}

  @doc """
  Checks if Explorer is available at runtime.
  """
  @spec explorer_available?() :: boolean()
  def explorer_available? do
    Code.ensure_loaded?(Explorer.DataFrame)
  end

  @doc """
  Converts query result to DataFrame if Explorer is available,
  otherwise returns as map.

  ## Examples

      # With Explorer available
      result_map = %{"col1" => [1, 2, 3], "col2" => ["a", "b", "c"]}
      DataFrame.from_result(result_map)
      # => %Explorer.DataFrame{...}

      # Without Explorer
      DataFrame.from_result(result_map)
      # => %{"col1" => [1, 2, 3], "col2" => ["a", "b", "c"]}
  """
  @spec from_result(map()) :: Explorer.DataFrame.t() | map()
  def from_result(result_map) when is_map(result_map) do
    if explorer_available?() do
      Explorer.DataFrame.new(result_map)
    else
      result_map
    end
  end

  @doc """
  Returns the type of data structure used for results.

  Returns `:dataframe` if Explorer is available, `:map` otherwise.
  """
  @spec result_type() :: :dataframe | :map
  def result_type do
    if explorer_available?(), do: :dataframe, else: :map
  end
end
