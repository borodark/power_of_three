defmodule PowerOfThree.MandataCaptateTest do
  use ExUnit.Case, async: false
  alias Adbc.{Database, Connection, Result}
  require Explorer.DataFrame, as: DF
  require Logger

  @moduletag :performance

  # Configuration
  @cube_driver_path Path.join(:code.priv_dir(:adbc), "lib/libadbc_driver_cube.so")
  @cube_host "localhost"
  @cube_adbc_port 8120
  @http_port 4008
  @cube_token "test"

  setup_all do
    unless File.exists?(@cube_driver_path) do
      raise "Cube driver not found at #{@cube_driver_path}"
    end

    # Verify CubeSQL is running
    case :gen_tcp.connect(String.to_charlist(@cube_host), @cube_adbc_port, [:binary], 1000) do
      {:ok, socket} -> :gen_tcp.close(socket)
      {:error, _} -> raise "cubesqld not running on #{@cube_host}:#{@cube_adbc_port}"
    end

    # Verify Cube API is running
    case Req.get("http://#{@cube_host}:#{@http_port}/cubejs-api/v1/meta") do
      {:ok, %{status: 200}} -> :ok
      _ -> raise "Cube API not running on #{@cube_host}:#{@http_port}"
    end

    :ok
  end

  setup do
    db =
      start_supervised!(
        {Database,
         driver: @cube_driver_path,
         "adbc.cube.host": @cube_host,
         "adbc.cube.port": Integer.to_string(@cube_adbc_port),
         "adbc.cube.connection_mode": "native",
         "adbc.cube.token": @cube_token}
      )

    conn = start_supervised!({Connection, database: db})
    %{arrow_conn: conn}
  end

  # Helper: Execute query via ADBC(Arrow Native)
  defp measure_arrow(conn, query, label) do
    IO.puts("\n🔍 ADBC(Arrow Native) Query: #{label}")

    start = System.monotonic_time(:millisecond)
    result = Connection.query(conn, query)
    time_query = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, result} ->
        start_mat = System.monotonic_time(:millisecond)
        materialized = Result.materialize(result)
        time_mat = System.monotonic_time(:millisecond) - start_mat

        df = adbc_to_dataframe(materialized)
        row_count = DF.n_rows(df)

        IO.puts("✅ #{row_count} rows | #{time_query}ms query + #{time_mat}ms materialize")

        %{
          method: "ADBC(Arrow Native)",
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
          method: "ADBC(Arrow Native)",
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

  # Helper: Execute query via HTTP API
  defp measure_http(query_map, label) do
    query_json = Jason.encode!(query_map)
    url = "http://#{@cube_host}:#{@http_port}/cubejs-api/v1/load"

    IO.puts("\n🌐 HTTP API Query: #{label}")

    start = System.monotonic_time(:millisecond)

    response =
      Req.get!(url,
        params: [query: query_json],
        headers: [{"Authorization", @cube_token}]
      )

    time_query = System.monotonic_time(:millisecond) - start

    start_mat = System.monotonic_time(:millisecond)
    data = get_in(response.body, ["data"]) || []
    pre_aggs = get_in(response.body, ["usedPreAggregations"])

    df = if length(data) > 0, do: DF.new(data), else: DF.new(%{})
    time_mat = System.monotonic_time(:millisecond) - start_mat

    IO.puts("✅ #{length(data)} rows | #{time_query}ms query + #{time_mat}ms materialize")

    if pre_aggs && map_size(pre_aggs) > 0 do
      IO.puts("📊 Pre-aggregations used:")

      Enum.each(pre_aggs, fn {_name, meta} ->
        table = meta["targetTableName"] || "unknown"
        IO.puts("   - #{table}")
      end)
    end

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
      column_data =
        Enum.map(columns, fn col ->
          {col.name, Adbc.Column.to_list(col)}
        end)
        |> Map.new()

      DF.new(column_data)
    end
  end

  # Helper: Print comparison
  defp print_comparison(arrow_result, http_result) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("📊 PERFORMANCE COMPARISON")
    IO.puts(String.duplicate("=", 80))

    IO.puts("\n🔷 ADBC(Arrow Native):")

    if arrow_result.success do
      IO.puts("  Query:  #{arrow_result.time_query}ms")
      IO.puts("  Mat:    #{arrow_result.time_materialize}ms")
      IO.puts("  TOTAL:  #{arrow_result.time_total}ms")
      IO.puts("  Rows:   #{arrow_result.row_count}")
    else
      IO.puts("  ❌ Failed: #{inspect(arrow_result.error)}")
    end

    IO.puts("\n🔶 HTTP API:")
    IO.puts("  Query:  #{http_result.time_query}ms")
    IO.puts("  Mat:    #{http_result.time_materialize}ms")
    IO.puts("  TOTAL:  #{http_result.time_total}ms")
    IO.puts("  Rows:   #{http_result.row_count}")

    if arrow_result.success && http_result.success do
      speedup = http_result.time_total / max(arrow_result.time_total, 1)
      diff = http_result.time_total - arrow_result.time_total

      IO.puts("\n📈 Result:")

      if arrow_result.time_total < http_result.time_total do
        IO.puts("  ⚡ ADBC(Arrow Native) is #{Float.round(speedup, 2)}x FASTER (saved #{diff}ms)")
      else
        IO.puts("  ⚠️  HTTP API is faster by #{abs(diff)}ms")
      end

      if arrow_result.row_count == http_result.row_count do
        IO.puts("  ✅ Row counts match: #{arrow_result.row_count}")
      else
        IO.puts(
          "  ⚠️  Row count mismatch! ADBC: #{arrow_result.row_count}, HTTP: #{http_result.row_count}"
        )
      end
    end

    IO.puts(String.duplicate("=", 80))
  end

  describe "Non-Time-Dimension Pre-Aggregation Tests" do
    test "1. Simple aggregation - No time dimension, 2D × 4M", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 1: Simple Aggregation (No Time Dimension)")
      IO.puts("Pre-agg: sums_and_count (market_code, brand_code)")
      IO.puts(String.duplicate("=", 80))

      # Query without time filter - should use sums_and_count pre-agg
      sql = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount,
        MEASURE(mandata_captate.tax_amount_sum) as tax_amount,
        MEASURE(mandata_captate.subtotal_amount_sum) as subtotal
      FROM mandata_captate
      GROUP BY 1, 2
      ORDER BY count DESC
      LIMIT 100
      """

      http_query = %{
        "measures" => [
          "mandata_captate.count",
          "mandata_captate.total_amount_sum",
          "mandata_captate.tax_amount_sum",
          "mandata_captate.subtotal_amount_sum"
        ],
        "dimensions" => ["mandata_captate.market_code", "mandata_captate.brand_code"],
        "order" => [["mandata_captate.count", "desc"]],
        "limit" => 100
      }

      arrow_result = measure_arrow(conn, sql, "No-Time 2D×4M")
      http_result = measure_http(http_query, "No-Time 2D×4M")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
      # Row counts should match
      assert arrow_result.row_count == http_result.row_count
    end

    test "2. Four dimensions - No time dimension, 4D × 4M", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 2: Four Dimensions (No Time Dimension)")
      IO.puts("Pre-agg: sums_and_count (market, brand, financial_status, fulfillment_status)")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        mandata_captate.financial_status,
        mandata_captate.fulfillment_status,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount,
        MEASURE(mandata_captate.tax_amount_sum) as tax_amount,
        MEASURE(mandata_captate.subtotal_amount_sum) as subtotal
      FROM mandata_captate
      GROUP BY 1, 2, 3, 4
      ORDER BY count DESC
      LIMIT 500
      """

      http_query = %{
        "measures" => [
          "mandata_captate.count",
          "mandata_captate.total_amount_sum",
          "mandata_captate.tax_amount_sum",
          "mandata_captate.subtotal_amount_sum"
        ],
        "dimensions" => [
          "mandata_captate.market_code",
          "mandata_captate.brand_code",
          "mandata_captate.financial_status",
          "mandata_captate.fulfillment_status"
        ],
        "order" => [["mandata_captate.count", "desc"]],
        "limit" => 500
      }

      arrow_result = measure_arrow(conn, sql, "No-Time 4D×4M")
      http_result = measure_http(http_query, "No-Time 4D×4M")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
      assert arrow_result.row_count == http_result.row_count
    end

    test "3. All measures - No time dimension, 2D × 6M", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 3: All Measures (No Time Dimension)")
      IO.puts("Pre-agg: sums_and_count (all 6 measures)")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount,
        MEASURE(mandata_captate.tax_amount_sum) as tax_amount,
        MEASURE(mandata_captate.subtotal_amount_sum) as subtotal,
        MEASURE(mandata_captate.discount_total_amount_sum) as discount,
        MEASURE(mandata_captate.delivery_subtotal_amount_sum) as delivery
      FROM mandata_captate
      GROUP BY 1, 2
      ORDER BY count DESC
      LIMIT 1000
      """

      http_query = %{
        "measures" => [
          "mandata_captate.count",
          "mandata_captate.total_amount_sum",
          "mandata_captate.tax_amount_sum",
          "mandata_captate.subtotal_amount_sum",
          "mandata_captate.discount_total_amount_sum",
          "mandata_captate.delivery_subtotal_amount_sum"
        ],
        "dimensions" => ["mandata_captate.market_code", "mandata_captate.brand_code"],
        "order" => [["mandata_captate.count", "desc"]],
        "limit" => 1000
      }

      arrow_result = measure_arrow(conn, sql, "No-Time 2D×6M")
      http_result = measure_http(http_query, "No-Time 2D×6M")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
      assert arrow_result.row_count == http_result.row_count
    end

    test "4. Large result set - No time dimension, 10K rows", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 4: Large Result Set (No Time Dimension, 10K rows)")
      IO.puts("Pre-agg: sums_and_count")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        mandata_captate.financial_status,
        mandata_captate.fulfillment_status,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      GROUP BY 1, 2, 3, 4
      ORDER BY count DESC
      LIMIT 10000
      """

      http_query = %{
        "measures" => [
          "mandata_captate.count",
          "mandata_captate.total_amount_sum"
        ],
        "dimensions" => [
          "mandata_captate.market_code",
          "mandata_captate.brand_code",
          "mandata_captate.financial_status",
          "mandata_captate.fulfillment_status"
        ],
        "order" => [["mandata_captate.count", "desc"]],
        "limit" => 10000
      }

      arrow_result = measure_arrow(conn, sql, "No-Time 4D×2M 10K")
      http_result = measure_http(http_query, "No-Time 4D×2M 10K")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
    end
  end

  describe "Compare: With vs Without Time Dimension" do
    test "5. With time dimension - Should use daily pre-agg", %{arrow_conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 5: WITH Time Dimension (Should use sums_and_count_daily)")
      IO.puts(String.duplicate("=", 80))

      sql = """
      SELECT
        DATE_TRUNC('day', mandata_captate.updated_at) as day,
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      WHERE mandata_captate.updated_at >= '2024-01-01'
        AND mandata_captate.updated_at < '2024-12-31'
      GROUP BY 1, 2, 3
      ORDER BY day DESC, count DESC
      LIMIT 1000
      """

      http_query = %{
        "measures" => [
          "mandata_captate.count",
          "mandata_captate.total_amount_sum"
        ],
        "dimensions" => ["mandata_captate.market_code", "mandata_captate.brand_code"],
        "timeDimensions" => [
          %{
            "dimension" => "mandata_captate.updated_at",
            "granularity" => "day",
            "dateRange" => ["2024-01-01", "2024-12-31"]
          }
        ],
        "order" => [["mandata_captate.count", "desc"]],
        "limit" => 1000
      }

      arrow_result = measure_arrow(conn, sql, "With-Time Daily")
      http_result = measure_http(http_query, "With-Time Daily")

      print_comparison(arrow_result, http_result)

      assert arrow_result.success
      assert http_result.success
    end
  end
end
