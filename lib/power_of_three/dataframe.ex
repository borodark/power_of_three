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

  ## ADBC Query Support

  Execute queries directly via ADBC and get DataFrames:

      # Using PowerOfThree query options
      {:ok, df} = CubeFrame.from_query(
        conn,
        columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
        limit: 10
      )

      # Or use raw SQL
      {:ok, df} = CubeFrame.from_query(conn, "SELECT brand_code, COUNT(*) FROM of_customers LIMIT 10")
  """

  alias PowerOfThree.CubeSqlGenerator

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
  Executes a query via ADBC and returns an Explorer.DataFrame.

  Similar to `Explorer.DataFrame.from_query/4`, but integrates with PowerOfThree
  query options (dimensions, measures, filters).

  ## Arguments

    * `conn` - ADBC connection (from `CubeConnection.connect/1` or pool)
    * `query_or_opts` - Either a SQL string or PowerOfThree query options
    * `params` - Query parameters (default: [])
    * `opts` - Additional options (default: [])
      * `:cube_opts` - Cube REST API connection options (host, port, token)

  ## Examples

      # Using PowerOfThree query options (leverages Cube's SQL generation)
      {:ok, df} = CubeFrame.from_query(
        conn,
        [
          columns: [Order.Dimensions.brand_code(), Order.Measures.count()],
          where: "brand_code = 'Nike'",
          limit: 10
        ],
        [],
        cube_opts: [host: "localhost", port: 4008, token: "test"]
      )

      # Using raw SQL
      {:ok, df} = CubeFrame.from_query(conn, "SELECT * FROM orders_no_preagg LIMIT 10")
  """
  @spec from_query(
          Adbc.Connection.t(),
          String.t() | keyword(),
          list(),
          keyword()
        ) :: {:ok, Explorer.DataFrame.t()} | {:error, term()}
  def from_query(conn, query_or_opts, params \\ [], opts \\ [])

  def from_query(conn, sql, params, opts) when is_binary(sql) do
    # Direct SQL query
    case Explorer.DataFrame.from_query(conn, sql, params, opts) do
      {:ok, df} -> {:ok, df}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  def from_query(conn, query_opts, _params, opts) when is_list(query_opts) do
    # PowerOfThree query options - get SQL from Cube's /v1/sql endpoint
    cube_opts = Keyword.get(opts, :cube_opts, [])
    # Remove cube_opts from opts before passing to Explorer
    explorer_opts = Keyword.delete(opts, :cube_opts)

    case CubeSqlGenerator.generate_sql(query_opts, cube_opts) do
      {:ok, sql} ->
        case Explorer.DataFrame.from_query(conn, sql, [], explorer_opts) do
          {:ok, df} -> {:ok, df}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  @doc """
  Executes a query via ADBC and returns an Explorer.DataFrame, raising on error.

  Similar to `Explorer.DataFrame.from_query!/4`, but integrates with PowerOfThree
  query options (dimensions, measures, filters).

  ## Arguments

    * `conn` - ADBC connection (from `CubeConnection.connect/1` or pool)
    * `query_or_opts` - Either a SQL string or PowerOfThree query options
    * `params` - Query parameters (default: [])
    * `opts` - Additional options (default: [])

  ## Examples

      # Using PowerOfThree query options
      df = CubeFrame.from_query!(
        conn,
        [
          columns: [Order.Dimensions.brand_code(), Order.Measures.count()],
          where: "brand_code = 'Nike'",
          limit: 10
        ]
      )

      # Using raw SQL
      df = CubeFrame.from_query!(conn, "SELECT * FROM orders_no_preagg LIMIT 10")
  """
  @spec from_query!(
          Adbc.Connection.t(),
          String.t() | keyword(),
          list(),
          keyword()
        ) :: Explorer.DataFrame.t()
  def from_query!(conn, query_or_opts, params \\ [], opts \\ [])

  def from_query!(conn, sql, params, opts) when is_binary(sql) do
    # Direct SQL query
    Explorer.DataFrame.from_query!(conn, sql, params, opts)
  end

  def from_query!(conn, query_opts, _params, opts) when is_list(query_opts) do
    # PowerOfThree query options - get SQL from Cube's /v1/sql endpoint
    cube_opts = Keyword.get(opts, :cube_opts, [])
    # Remove cube_opts from opts before passing to Explorer
    explorer_opts = Keyword.delete(opts, :cube_opts)

    case CubeSqlGenerator.generate_sql(query_opts, cube_opts) do
      {:ok, sql} ->
        Explorer.DataFrame.from_query!(conn, sql, [], explorer_opts)

      {:error, reason} ->
        raise "Failed to generate SQL from Cube: #{inspect(reason)}"
    end
  end

  def result_type, do: :dataframe
end
