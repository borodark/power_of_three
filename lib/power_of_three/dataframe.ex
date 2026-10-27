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

  ## Arrow Native Query Support

  Execute queries over Cube's Arrow Native protocol and get DataFrames:

      {:ok, client} = PowerOfThree.CubeNativeClient.connect(token: "test")

      # Using PowerOfThree query options
      {:ok, df} = CubeFrame.from_query(
        client,
        columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
        limit: 10
      )

      # Or use raw SQL
      {:ok, df} = CubeFrame.from_query(client, "SELECT brand_code, COUNT(*) FROM of_customers LIMIT 10")
  """

  alias PowerOfThree.{CubeNativeClient, CubeSqlGenerator}

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
        # Empty Series
        Explorer.Series.from_list([])

      1 ->
        # Single column series
        [col] = Map.keys(result_map)
        Explorer.Series.from_list(result_map[col])

      _ ->
        # General case
        Explorer.DataFrame.new(result_map)
    end
  end

  def from_result(%{}), do: Explorer.Series.from_list([])

  @doc """
  Executes a query over the Arrow Native protocol and returns an Explorer.DataFrame.

  ## Arguments

    * `client` - a `PowerOfThree.CubeNativeClient` (from `CubeNativeClient.connect/1` or the pool)
    * `query_or_opts` - Either a SQL string or PowerOfThree query options
    * `params` - Must be `[]`; the Arrow Native protocol has no parameter binding
    * `opts` - Additional options (default: [])
      * `:cube_opts` - Cube REST API connection options (host, port, token)

  ## Examples

      # Using PowerOfThree query options (leverages Cube's SQL generation)
      {:ok, df} = CubeFrame.from_query(
        client,
        [
          columns: [Order.Dimensions.brand_code(), Order.Measures.count()],
          where: "brand_code = 'Nike'",
          limit: 10
        ],
        [],
        cube_opts: [host: "localhost", port: 4008, token: "test"]
      )

      # Using raw SQL
      {:ok, df} = CubeFrame.from_query(client, "SELECT * FROM orders_no_preagg LIMIT 10")
  """
  @spec from_query(CubeNativeClient.t(), String.t() | keyword(), list(), keyword()) ::
          {:ok, Explorer.DataFrame.t()} | {:error, term()}
  def from_query(client, query_or_opts, params \\ [], opts \\ [])

  def from_query(%CubeNativeClient{} = client, sql, [], _opts) when is_binary(sql) do
    CubeNativeClient.query_df(client, sql)
  end

  def from_query(%CubeNativeClient{}, sql, _params, _opts) when is_binary(sql) do
    {:error, :params_not_supported_by_native_transport}
  end

  def from_query(%CubeNativeClient{} = client, query_opts, params, opts) when is_list(query_opts) do
    # PowerOfThree query options - get SQL from Cube's /v1/sql endpoint
    cube_opts = Keyword.get(opts, :cube_opts, [])

    case CubeSqlGenerator.generate_sql(query_opts, cube_opts) do
      {:ok, sql} -> from_query(client, sql, params, Keyword.delete(opts, :cube_opts))
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Same as `from_query/4`, but returns the DataFrame or raises.

  ## Examples

      df = CubeFrame.from_query!(client, "SELECT * FROM orders_no_preagg LIMIT 10")
  """
  @spec from_query!(CubeNativeClient.t(), String.t() | keyword(), list(), keyword()) ::
          Explorer.DataFrame.t()
  def from_query!(client, query_or_opts, params \\ [], opts \\ []) do
    case from_query(client, query_or_opts, params, opts) do
      {:ok, df} -> df
      {:error, reason} -> raise "Cube query failed: #{inspect(reason)}"
    end
  end

  def result_type, do: :dataframe
end
