defmodule PowerOfThree.CubeSqlGenerator do
  @moduledoc """
  Generates SQL queries by leveraging Cube's /v1/sql endpoint.

  Instead of implementing our own SQL generation logic, this module:
  1. Converts PowerOfThree query options to Cube REST API format
  2. Calls Cube's /v1/sql endpoint to get the optimized SQL
  3. Returns the SQL for execution via ADBC

  This approach ensures consistency with Cube's query semantics and
  automatically handles pre-aggregations, rollups, and optimizations.

  ## Important Notes

  - WHERE clause support is provided by delegating to `CubeQueryTranslator`
  - The SQL returned by Cube's /v1/sql endpoint may reference pre-aggregation
    tables that only exist within Cube's internal cache/database. When using
    ADBC to query directly against your database, these pre-aggregation tables
    may not exist. For ADBC with PowerOfThree query options to work, the cube
    must either:
    - Not have pre-aggregations configured (e.g., cubes with "no_preagg" suffix)
    - Have external pre-aggregations materialized in the target database
  - For maximum compatibility with ADBC, prefer using raw SQL against base tables
  - MySQL backticks in generated SQL are automatically converted to PostgreSQL
    double quotes for ADBC compatibility
  """

  alias PowerOfThree.CubeQueryTranslator

  @doc """
  Generates SQL by calling Cube's /v1/sql endpoint.

  ## Arguments

    * `query_opts` - PowerOfThree query options (columns, where, limit, etc.)
    * `cube_opts` - Cube connection options (host, port, token)

  ## Examples

      {:ok, sql} = CubeSqlGenerator.generate_sql(
        [
          columns: [Order.Dimensions.brand_code(), Order.Measures.count()],
          limit: 10
        ],
        host: "localhost",
        port: 4008,
        token: "test"
      )
  """
  @spec generate_sql(keyword(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_sql(query_opts, cube_opts \\ []) do
    with {:ok, cube_query} <- to_cube_query(query_opts),
         {:ok, sql} <- fetch_sql_from_cube(cube_query, cube_opts) do
      {:ok, sql}
    end
  end

  @doc """
  Converts PowerOfThree query options to Cube REST API query format.

  ## Examples

      {:ok, cube_query} = CubeSqlGenerator.to_cube_query([
        columns: [
          %DimensionRef{name: :market_code, module: Order},
          %MeasureRef{name: :count, module: Order}
        ],
        limit: 5
      ])

      # Returns:
      # %{
      #   "dimensions" => ["orders_no_preagg.market_code"],
      #   "measures" => ["orders_no_preagg.count"],
      #   "limit" => 5
      # }
  """
  @spec to_cube_query(keyword()) :: {:ok, map()} | {:error, term()}
  def to_cube_query(query_opts) do
    # Delegate to CubeQueryTranslator which has full WHERE clause parsing support
    CubeQueryTranslator.to_cube_query(query_opts)
  end

  @doc """
  Fetches SQL from Cube's /v1/sql endpoint.

  ## Arguments

    * `cube_query` - Cube REST API query format
    * `opts` - Connection options (host, port, token)

  ## Examples

      {:ok, sql} = CubeSqlGenerator.fetch_sql_from_cube(
        %{"dimensions" => ["orders.market_code"], "measures" => ["orders.count"]},
        host: "localhost",
        port: 4008,
        token: "test"
      )
  """
  @spec fetch_sql_from_cube(map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def fetch_sql_from_cube(cube_query, opts \\ []) do
    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, 4008)
    token = Keyword.get(opts, :token, "test")

    url = "http://#{host}:#{port}/cubejs-api/v1/sql"

    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", token}
    ]

    body = Jason.encode!(%{"query" => cube_query})

    case Req.post(url, headers: headers, body: body) do
      {:ok, %{status: 200, body: response}} ->
        # Extract SQL from response
        case response do
          %{"sql" => %{"sql" => [sql | _]}} ->
            {:ok, sql}

          _ ->
            {:error, "Invalid response format from Cube /v1/sql endpoint"}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "Cube /v1/sql returned status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

end
