defmodule PowerOfThree.HttpVsArrowPerformanceTest do
  use ExUnit.Case, async: false
  alias Adbc.{Database, Connection, Result}
  require Explorer.DataFrame, as: DF
  require Logger

  @moduletag :performance

  # Configuration
  @cube_driver_path Path.join(:code.priv_dir(:adbc), "lib/libadbc_driver_cube.so")
  @cube_host "localhost"
  @arrow_port 4445
  @http_port 4008
  @cube_token "test"

  setup_all do
    unless File.exists?(@cube_driver_path) do
      raise "Cube driver not found at #{@cube_driver_path}"
    end

    # Verify CubeSQL is running (Arrow IPC)
    case :gen_tcp.connect(String.to_charlist(@cube_host), @arrow_port, [:binary], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)

      {:error, _} ->
        raise RuntimeError, """
        cubesqld not running on #{@cube_host}:#{@arrow_port}.
        """
    end

    # Verify Cube API is running (HTTP)
    case Req.get("http://#{@cube_host}:#{@http_port}/cubejs-api/v1/meta") do
      {:ok, %{status: 200}} ->
        :ok

      _ ->
        raise RuntimeError, """
        Cube API not running on #{@cube_host}:#{@http_port}.
        """
    end

    :ok
  end

  setup do
    # Setup Arrow connection
    db = start_supervised!(
      {Database,
       driver: @cube_driver_path,
       "adbc.cube.host": @cube_host,
       "adbc.cube.port": Integer.to_string(@arrow_port),
       "adbc.cube.connection_mode": "native",
       "adbc.cube.token": @cube_token}
    )

    conn = start_supervised!({Connection, database: db})

    %{arrow_conn: conn}
  end

  # Helper: Execute query via Arrow IPC and convert to DataFrame
  defp measure_arrow(conn, query, label) do
    IO.puts("\n🔍 Arrow IPC Query: #{label}")

    start = System.monotonic_time(:millisecond)
    result = Connection.query(conn, query)
    time_query = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, result} ->
        start_mat = System.monotonic_time(:millisecond)
        materialized = Result.materialize(result)
        time_mat = System.monotonic_time(:millisecond) - start_mat

        # Convert to DataFrame
        df = adbc_to_dataframe(materialized)
        row_count = DF.n_rows(df)

        IO.puts("✅ #{row_count} rows, #{DF.n_columns(df)} columns | #{time_query}ms query + #{time_mat}ms materialize")

        %{
          method: "Arrow IPC",
          label: label,
          time_query: time_query,
          time_materialize: time_mat,
          time_total: time_query + time_mat,
          row_count: row_count,
          dataframe: df,
          success: true
        }

      {:error, error} ->
        IO.puts("❌ Error: #{inspect(error)}")

        %{
          method: "Arrow IPC",
          label: label,
          time_query: time_query,
          time_materialize: 0,
          time_total: time_query,
          row_count: 0,
          dataframe: nil,
          success: false,
          error: error
        }
    end
  end

  # Helper: Execute query via HTTP API and convert to DataFrame
  defp measure_http(query_map, label) do
    query_json = Jason.encode!(query_map)
    url = "http://#{@cube_host}:#{@http_port}/cubejs-api/v1/load"

    IO.puts("\n🌐 HTTP API Query: #{label}")

    start = System.monotonic_time(:millisecond)
    response = Req.get!(url,
      params: [query: query_json],
      headers: [{"Authorization", @cube_token}]
    )
    time_query = System.monotonic_time(:millisecond) - start

    start_mat = System.monotonic_time(:millisecond)
    data = get_in(response.body, ["data"]) || []
    pre_aggs = get_in(response.body, ["usedPreAggregations"])

    # Convert to DataFrame
    df = if length(data) > 0 do
      DF.new(data)
    else
      DF.new(%{})
    end

    time_mat = System.monotonic_time(:millisecond) - start_mat

    IO.puts("✅ #{length(data)} rows, #{DF.n_columns(df)} columns | #{time_query}ms query + #{time_mat}ms materialize")

    %{
      method: "HTTP API",
      label: label,
      time_query: time_query,
      time_materialize: time_mat,
      time_total: time_query + time_mat,
      row_count: length(data),
      dataframe: df,
      pre_aggs: pre_aggs,
      success: true
    }
  end

  # Convert ADBC Result to Explorer DataFrame
  defp adbc_to_dataframe(%Result{data: columns}) when is_list(columns) do
    if length(columns) == 0 do
      DF.new(%{})
    else
      # Convert each column to a list and create a map
      column_data = Enum.map(columns, fn col ->
        {col.name, Adbc.Column.to_list(col)}
      end)
      |> Map.new()

      DF.new(column_data)
    end
  end

  # Helper: Warmup
  defp warmup(conn, sql_query, http_query_map, rounds \\ 2) do
    IO.puts("\n🔥 Warming up (#{rounds} rounds)...")
    for _ <- 1..rounds do
      Connection.query(conn, sql_query)
      measure_http(http_query_map, "warmup")
    end
    :ok
  end

  # Helper: Print results comparison with DataFrame summary
  defp print_comparison(arrow_result, http_result) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("📊 PERFORMANCE COMPARISON")
    IO.puts(String.duplicate("=", 80))

    IO.puts("\n🔷 Arrow IPC (CubeStore Direct):")
    if arrow_result.success do
      IO.puts("  ✅ Success")
      IO.puts("  Query:         #{arrow_result.time_query}ms")
      IO.puts("  Materialize:   #{arrow_result.time_materialize}ms")
      IO.puts("  TOTAL:         #{arrow_result.time_total}ms")
      IO.puts("  Rows:          #{arrow_result.row_count}")
    else
      IO.puts("  ❌ Failed: #{inspect(arrow_result.error)}")
    end

    IO.puts("\n🔶 HTTP API (with pre-agg):")
    IO.puts("  ✅ Success")
    IO.puts("  Query:         #{http_result.time_query}ms")
    IO.puts("  Materialize:   #{http_result.time_materialize}ms")
    IO.puts("  TOTAL:         #{http_result.time_total}ms")
    IO.puts("  Rows:          #{http_result.row_count}")

    if arrow_result.success && http_result.success do
      speedup = http_result.time_total / max(arrow_result.time_total, 1)
      diff = http_result.time_total - arrow_result.time_total

      IO.puts("\n📈 Performance Result:")
      if arrow_result.time_total < http_result.time_total do
        IO.puts("  ⚡ Arrow IPC is #{Float.round(speedup, 2)}x FASTER (saved #{diff}ms)")
      else
        IO.puts("  ⚠️  HTTP API is faster by #{abs(diff)}ms (protocol overhead)")
      end

      if arrow_result.row_count != http_result.row_count do
        IO.puts("  ⚠️  WARNING: Row count mismatch! Arrow: #{arrow_result.row_count}, HTTP: #{http_result.row_count}")
      else
        IO.puts("  ✅ Row counts match: #{arrow_result.row_count}")
      end

      # Compare DataFrames
      if arrow_result.dataframe && http_result.dataframe do
        print_dataframe_comparison(arrow_result.dataframe, http_result.dataframe)
      end
    end

    IO.puts(String.duplicate("=", 80))
  end

  # Helper: Compare DataFrames using Explorer
  defp print_dataframe_comparison(arrow_df, http_df) do
    IO.puts("\n📊 DATA COMPARISON (Explorer DataFrame)")
    IO.puts(String.duplicate("-", 80))

    if DF.n_rows(arrow_df) > 0 && DF.n_rows(http_df) > 0 do
      # Check if column names match
      arrow_cols = DF.names(arrow_df) |> Enum.sort()
      http_cols = DF.names(http_df) |> Enum.sort()

      if arrow_cols == http_cols do
        IO.puts("\n✅ Column schemas match: #{inspect(arrow_cols)}")

        # Show first few rows of each
        IO.puts("\n🔷 Arrow IPC Data (first 3 rows):")
        arrow_df |> DF.head(3) |> IO.inspect(limit: :infinity)

        IO.puts("\n🔶 HTTP API Data (first 3 rows):")
        http_df |> DF.head(3) |> IO.inspect(limit: :infinity)

        # Calculate summary statistics for numeric columns
        numeric_cols = arrow_df
        |> DF.dtypes()
        |> Enum.filter(fn {_name, dtype} -> dtype in [:integer, :float, :s64, :f64] end)
        |> Enum.map(fn {name, _dtype} -> name end)

        if length(numeric_cols) > 0 do
          IO.puts("\n📊 Numeric Column Statistics (from Arrow IPC):")
          for col <- numeric_cols do
            series = DF.pull(arrow_df, col)
            IO.puts("  #{col}:")
            IO.puts("    Min:  #{Explorer.Series.min(series)}")
            IO.puts("    Max:  #{Explorer.Series.max(series)}")
            IO.puts("    Mean: #{Explorer.Series.mean(series) |> Float.round(2)}")
          end
        end
      else
        IO.puts("\n⚠️  Column schemas differ:")
        IO.puts("  Arrow: #{inspect(arrow_cols)}")
        IO.puts("  HTTP:  #{inspect(http_cols)}")
      end
    end
  end

  describe "HTTP vs Arrow Performance Tests" do
    test "1. Simple aggregation - 2 dimensions, 2 measures, 100 rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 1: Simple Aggregation - Market & Brand Analysis")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        orders_with_preagg.market_code,
        orders_with_preagg.brand_code,
        MEASURE(orders_with_preagg.count) as order_count,
        MEASURE(orders_with_preagg.total_amount_sum) as total_amount
      FROM orders_with_preagg
      GROUP BY 1, 2
      ORDER BY order_count DESC
      LIMIT 100
      """

      http_query = %{
        "measures" => ["orders_with_preagg.count", "orders_with_preagg.total_amount_sum"],
        "dimensions" => ["orders_with_preagg.market_code", "orders_with_preagg.brand_code"],
        "order" => [["orders_with_preagg.count", "desc"]],
        "limit" => 100
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Simple 2D x 2M")
      http_result = measure_http(http_query, "Simple 2D x 2M")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
      assert arrow_result.row_count == http_result.row_count
    end

    test "2. Daily time series - 3 dimensions, 4 measures, 200 rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 2: Daily Time Series - Multi-measure Analysis")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('day', orders_with_preagg.updated_at) as day,
        orders_with_preagg.market_code,
        orders_with_preagg.brand_code,
        MEASURE(orders_with_preagg.count) as order_count,
        MEASURE(orders_with_preagg.total_amount_sum) as total_amount,
        MEASURE(orders_with_preagg.tax_amount_sum) as tax_amount,
        MEASURE(orders_with_preagg.subtotal_amount_sum) as subtotal
      FROM orders_with_preagg
      WHERE orders_with_preagg.updated_at >= '2024-01-01'
        AND orders_with_preagg.updated_at < '2024-12-31'
      GROUP BY 1, 2, 3
      ORDER BY day DESC, order_count DESC
      LIMIT 200
      """

      http_query = %{
        "measures" => [
          "orders_with_preagg.count",
          "orders_with_preagg.total_amount_sum",
          "orders_with_preagg.tax_amount_sum",
          "orders_with_preagg.subtotal_amount_sum"
        ],
        "dimensions" => ["orders_with_preagg.market_code", "orders_with_preagg.brand_code"],
        "timeDimensions" => [
          %{
            "dimension" => "orders_with_preagg.updated_at",
            "granularity" => "day",
            "dateRange" => ["2024-01-01", "2024-12-31"]
          }
        ],
        "order" => [["orders_with_preagg.count", "desc"]],
        "limit" => 200
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Daily 3D x 4M")
      http_result = measure_http(http_query, "Daily 3D x 4M")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
      assert arrow_result.row_count == http_result.row_count
    end

    test "3. Monthly aggregation - 2 dimensions, 5 measures, 500 rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 3: Monthly Aggregation - All Measures")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('month', orders_with_preagg.updated_at) as month,
        orders_with_preagg.market_code,
        orders_with_preagg.brand_code,
        MEASURE(orders_with_preagg.count) as order_count,
        MEASURE(orders_with_preagg.total_amount_sum) as total_amount,
        MEASURE(orders_with_preagg.tax_amount_sum) as tax_amount,
        MEASURE(orders_with_preagg.subtotal_amount_sum) as subtotal,
        MEASURE(orders_with_preagg.customer_id_distinct) as unique_customers
      FROM orders_with_preagg
      WHERE orders_with_preagg.updated_at >= '2020-01-01'
        AND orders_with_preagg.updated_at < '2025-01-01'
      GROUP BY 1, 2, 3
      ORDER BY month DESC, order_count DESC
      LIMIT 500
      """

      http_query = %{
        "measures" => [
          "orders_with_preagg.count",
          "orders_with_preagg.total_amount_sum",
          "orders_with_preagg.tax_amount_sum",
          "orders_with_preagg.subtotal_amount_sum",
          "orders_with_preagg.customer_id_distinct"
        ],
        "dimensions" => ["orders_with_preagg.market_code", "orders_with_preagg.brand_code"],
        "timeDimensions" => [
          %{
            "dimension" => "orders_with_preagg.updated_at",
            "granularity" => "month",
            "dateRange" => ["2020-01-01", "2024-12-31"]
          }
        ],
        "order" => [["orders_with_preagg.count", "desc"]],
        "limit" => 500
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Monthly 3D x 5M")
      http_result = measure_http(http_query, "Monthly 3D x 5M")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
      assert arrow_result.row_count == http_result.row_count
    end

    test "4. Weekly time series - 1 dimension, 5 measures, 1000 rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 4: Weekly Time Series - Large Result Set")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('week', orders_with_preagg.updated_at) as week,
        orders_with_preagg.market_code,
        MEASURE(orders_with_preagg.count) as order_count,
        MEASURE(orders_with_preagg.total_amount_sum) as total_amount,
        MEASURE(orders_with_preagg.tax_amount_sum) as tax_amount,
        MEASURE(orders_with_preagg.subtotal_amount_sum) as subtotal,
        MEASURE(orders_with_preagg.customer_id_distinct) as unique_customers
      FROM orders_with_preagg
      WHERE orders_with_preagg.updated_at >= '2020-01-01'
        AND orders_with_preagg.updated_at < '2025-01-01'
      GROUP BY 1, 2
      ORDER BY week DESC, order_count DESC
      LIMIT 1000
      """

      http_query = %{
        "measures" => [
          "orders_with_preagg.count",
          "orders_with_preagg.total_amount_sum",
          "orders_with_preagg.tax_amount_sum",
          "orders_with_preagg.subtotal_amount_sum",
          "orders_with_preagg.customer_id_distinct"
        ],
        "dimensions" => ["orders_with_preagg.market_code"],
        "timeDimensions" => [
          %{
            "dimension" => "orders_with_preagg.updated_at",
            "granularity" => "week",
            "dateRange" => ["2020-01-01", "2024-12-31"]
          }
        ],
        "order" => [["orders_with_preagg.count", "desc"]],
        "limit" => 1000
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Weekly 2D x 5M")
      http_result = measure_http(http_query, "Weekly 2D x 5M")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
      assert arrow_result.row_count == http_result.row_count
    end

    test "5. Single dimension deep dive - 1 dimension, 4 measures, 50 rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 5: Single Dimension Deep Dive - Market Analysis")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        orders_with_preagg.market_code,
        MEASURE(orders_with_preagg.count) as order_count,
        MEASURE(orders_with_preagg.total_amount_sum) as total_amount,
        MEASURE(orders_with_preagg.tax_amount_sum) as tax_amount,
        MEASURE(orders_with_preagg.customer_id_distinct) as unique_customers
      FROM orders_with_preagg
      GROUP BY 1
      ORDER BY order_count DESC
      LIMIT 50
      """

      http_query = %{
        "measures" => [
          "orders_with_preagg.count",
          "orders_with_preagg.total_amount_sum",
          "orders_with_preagg.tax_amount_sum",
          "orders_with_preagg.customer_id_distinct"
        ],
        "dimensions" => ["orders_with_preagg.market_code"],
        "order" => [["orders_with_preagg.count", "desc"]],
        "limit" => 50
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Single 1D x 4M")
      http_result = measure_http(http_query, "Single 1D x 4M")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
      assert arrow_result.row_count == http_result.row_count
    end
  end

  describe "HTTP vs Arrow Large Scale Tests - Narrow Results" do
    test "6. Narrow result set - 2 columns, 10K rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 6: LARGE SCALE - Narrow (2 cols × 10K rows)")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('day', orders_with_preagg.updated_at) as day,
        MEASURE(orders_with_preagg.count) as order_count
      FROM orders_with_preagg
      WHERE orders_with_preagg.updated_at >= '2020-01-01'
        AND orders_with_preagg.updated_at < '2025-01-01'
      GROUP BY 1
      ORDER BY day DESC
      LIMIT 10000
      """

      http_query = %{
        "measures" => ["orders_with_preagg.count"],
        "timeDimensions" => [
          %{
            "dimension" => "orders_with_preagg.updated_at",
            "granularity" => "day",
            "dateRange" => ["2020-01-01", "2024-12-31"]
          }
        ],
        "limit" => 10000
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Narrow 2cols × 10K")
      http_result = measure_http(http_query, "Narrow 2cols × 10K")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
    end

    test "7. Narrow result set - 2 columns, 30K rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 7: LARGE SCALE - Narrow (2 cols × 30K rows)")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('hour', orders_with_preagg.updated_at) as hour,
        MEASURE(orders_with_preagg.count) as order_count
      FROM orders_with_preagg
      WHERE orders_with_preagg.updated_at >= '2020-01-01'
        AND orders_with_preagg.updated_at < '2025-01-01'
      GROUP BY 1
      ORDER BY hour DESC
      LIMIT 30000
      """

      http_query = %{
        "measures" => ["orders_with_preagg.count"],
        "timeDimensions" => [
          %{
            "dimension" => "orders_with_preagg.updated_at",
            "granularity" => "hour",
            "dateRange" => ["2020-01-01", "2024-12-31"]
          }
        ],
        "limit" => 30000
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Narrow 2cols × 30K")
      http_result = measure_http(http_query, "Narrow 2cols × 30K")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
    end

    test "8. Narrow result set - 2 columns, 50K rows (MAX LIMIT)", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 8: LARGE SCALE - Narrow (2 cols × 50K rows) ⚡ MAX LIMIT")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('hour', orders_with_preagg.updated_at) as hour,
        MEASURE(orders_with_preagg.count) as order_count
      FROM orders_with_preagg
      WHERE orders_with_preagg.updated_at >= '2015-01-01'
        AND orders_with_preagg.updated_at < '2025-01-01'
      GROUP BY 1
      ORDER BY hour DESC
      LIMIT 50000
      """

      http_query = %{
        "measures" => ["orders_with_preagg.count"],
        "timeDimensions" => [
          %{
            "dimension" => "orders_with_preagg.updated_at",
            "granularity" => "hour",
            "dateRange" => ["2015-01-01", "2024-12-31"]
          }
        ],
        "limit" => 50000
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Narrow 2cols × 50K MAX")
      http_result = measure_http(http_query, "Narrow 2cols × 50K MAX")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
    end
  end

  describe "HTTP vs Arrow Large Scale Tests - Wide Results" do
    test "9. Wide result set - 8 columns, 10K rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 9: LARGE SCALE - Wide (8 cols × 10K rows)")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('day', orders_with_preagg.updated_at) as day,
        orders_with_preagg.market_code,
        orders_with_preagg.brand_code,
        MEASURE(orders_with_preagg.count) as order_count,
        MEASURE(orders_with_preagg.total_amount_sum) as total_amount,
        MEASURE(orders_with_preagg.tax_amount_sum) as tax_amount,
        MEASURE(orders_with_preagg.subtotal_amount_sum) as subtotal,
        MEASURE(orders_with_preagg.customer_id_distinct) as unique_customers
      FROM orders_with_preagg
      WHERE orders_with_preagg.updated_at >= '2020-01-01'
        AND orders_with_preagg.updated_at < '2025-01-01'
      GROUP BY 1, 2, 3
      ORDER BY day DESC, order_count DESC
      LIMIT 10000
      """

      http_query = %{
        "measures" => [
          "orders_with_preagg.count",
          "orders_with_preagg.total_amount_sum",
          "orders_with_preagg.tax_amount_sum",
          "orders_with_preagg.subtotal_amount_sum",
          "orders_with_preagg.customer_id_distinct"
        ],
        "dimensions" => ["orders_with_preagg.market_code", "orders_with_preagg.brand_code"],
        "timeDimensions" => [
          %{
            "dimension" => "orders_with_preagg.updated_at",
            "granularity" => "day",
            "dateRange" => ["2020-01-01", "2024-12-31"]
          }
        ],
        "order" => [["orders_with_preagg.count", "desc"]],
        "limit" => 10000
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Wide 8cols × 10K")
      http_result = measure_http(http_query, "Wide 8cols × 10K")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
    end

    test "10. Wide result set - 8 columns, 30K rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 10: LARGE SCALE - Wide (8 cols × 30K rows)")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('hour', orders_with_preagg.updated_at) as hour,
        orders_with_preagg.market_code,
        orders_with_preagg.brand_code,
        MEASURE(orders_with_preagg.count) as order_count,
        MEASURE(orders_with_preagg.total_amount_sum) as total_amount,
        MEASURE(orders_with_preagg.tax_amount_sum) as tax_amount,
        MEASURE(orders_with_preagg.subtotal_amount_sum) as subtotal,
        MEASURE(orders_with_preagg.customer_id_distinct) as unique_customers
      FROM orders_with_preagg
      WHERE orders_with_preagg.updated_at >= '2020-01-01'
        AND orders_with_preagg.updated_at < '2025-01-01'
      GROUP BY 1, 2, 3
      ORDER BY hour DESC, order_count DESC
      LIMIT 30000
      """

      http_query = %{
        "measures" => [
          "orders_with_preagg.count",
          "orders_with_preagg.total_amount_sum",
          "orders_with_preagg.tax_amount_sum",
          "orders_with_preagg.subtotal_amount_sum",
          "orders_with_preagg.customer_id_distinct"
        ],
        "dimensions" => ["orders_with_preagg.market_code", "orders_with_preagg.brand_code"],
        "timeDimensions" => [
          %{
            "dimension" => "orders_with_preagg.updated_at",
            "granularity" => "hour",
            "dateRange" => ["2020-01-01", "2024-12-31"]
          }
        ],
        "order" => [["orders_with_preagg.count", "desc"]],
        "limit" => 30000
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Wide 8cols × 30K")
      http_result = measure_http(http_query, "Wide 8cols × 30K")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
    end

    test "11. Wide result set - 8 columns, 50K rows (MAX LIMIT)", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 11: LARGE SCALE - Wide (8 cols × 50K rows) ⚡ MAX LIMIT")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('hour', orders_with_preagg.updated_at) as hour,
        orders_with_preagg.market_code,
        orders_with_preagg.brand_code,
        MEASURE(orders_with_preagg.count) as order_count,
        MEASURE(orders_with_preagg.total_amount_sum) as total_amount,
        MEASURE(orders_with_preagg.tax_amount_sum) as tax_amount,
        MEASURE(orders_with_preagg.subtotal_amount_sum) as subtotal,
        MEASURE(orders_with_preagg.customer_id_distinct) as unique_customers
      FROM orders_with_preagg
      WHERE orders_with_preagg.updated_at >= '2015-01-01'
        AND orders_with_preagg.updated_at < '2025-01-01'
      GROUP BY 1, 2, 3
      ORDER BY hour DESC, order_count DESC
      LIMIT 50000
      """

      http_query = %{
        "measures" => [
          "orders_with_preagg.count",
          "orders_with_preagg.total_amount_sum",
          "orders_with_preagg.tax_amount_sum",
          "orders_with_preagg.subtotal_amount_sum",
          "orders_with_preagg.customer_id_distinct"
        ],
        "dimensions" => ["orders_with_preagg.market_code", "orders_with_preagg.brand_code"],
        "timeDimensions" => [
          %{
            "dimension" => "orders_with_preagg.updated_at",
            "granularity" => "hour",
            "dateRange" => ["2015-01-01", "2024-12-31"]
          }
        ],
        "order" => [["orders_with_preagg.count", "desc"]],
        "limit" => 50000
      }

      warmup(conn, sql, http_query, 1)

      IO.puts("\n📊 Running actual test...")
      arrow_result = measure_arrow(conn, sql, "Wide 8cols × 50K MAX")
      http_result = measure_http(http_query, "Wide 8cols × 50K MAX")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
    end
  end
end
