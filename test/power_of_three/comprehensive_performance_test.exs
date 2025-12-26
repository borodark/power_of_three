defmodule PowerOfThree.ComprehensivePerformanceTest do
  use ExUnit.Case, async: false
  alias Adbc.{Database, Connection, Result}

  @moduletag :performance

  # Path to Cube ADBC driver
  @cube_driver_path Path.join(:code.priv_dir(:adbc), "lib/libadbc_driver_cube.so")
  @cube_host "localhost"
  @cube_port 4445  # Arrow IPC port
  @cube_token "test"

  setup_all do
    unless File.exists?(@cube_driver_path) do
      raise "Cube driver not found at #{@cube_driver_path}"
    end

    # Verify cubesqld is running
    case :gen_tcp.connect(String.to_charlist(@cube_host), @cube_port, [:binary], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)

      {:error, _} ->
        raise RuntimeError, """
        cubesqld not running on #{@cube_host}:#{@cube_port}.
        Start with Arrow IPC support:
          cd ~/projects/learn_erl/cube/rust/cubesql
          CUBESQL_CUBESTORE_DIRECT=true \\
          CUBESQL_CUBE_URL=http://localhost:4008/cubejs-api \\
          CUBESQL_CUBESTORE_URL=ws://127.0.0.1:3030/ws \\
          CUBESQL_CUBE_TOKEN=test \\
          CUBESQL_PG_PORT=4444 \\
          CUBEJS_ARROW_PORT=4445 \\
          RUST_LOG=info \\
          ./target/debug/cubesqld
        """
    end

    :ok
  end

  setup do
    db = start_supervised!(
      {Database,
       driver: @cube_driver_path,
       "adbc.cube.host": @cube_host,
       "adbc.cube.port": Integer.to_string(@cube_port),
       "adbc.cube.connection_mode": "native",
       "adbc.cube.token": @cube_token}
    )

    conn = start_supervised!({Connection, database: db})
    %{conn: conn}
  end

  defp warmup(conn, query, rounds \\ 2) do
    for _ <- 1..rounds do
      Connection.query(conn, query)
    end

    :ok
  end

  defp measure_full_path(conn, query, label) do
    # Measure query execution
    start_query = System.monotonic_time(:millisecond)
    {:ok, result} = Connection.query(conn, query)
    time_query = System.monotonic_time(:millisecond) - start_query

    # Measure materialization (Result.materialize returns a map with data/columns)
    start_materialize = System.monotonic_time(:millisecond)
    materialized = Result.materialize(result)
    time_materialize = System.monotonic_time(:millisecond) - start_materialize

    time_total = time_query + time_materialize
    row_count = length(materialized.data)

    %{
      label: label,
      time_query: time_query,
      time_materialize: time_materialize,
      time_total: time_total,
      row_count: row_count,
      result: materialized
    }
  end

  describe "Comprehensive Performance Tests" do
    test "1. Small aggregation (few groups)", %{conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 1: Small Aggregation (Market x Brand groups)")
      IO.puts(String.duplicate("=", 80))

      query_with_preagg = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      GROUP BY 1, 2
      ORDER BY count DESC
      LIMIT 50
      """

      query_without_preagg = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.email,
        MEASURE(mandata_captate.count) as count
      FROM mandata_captate
      GROUP BY 1, 2
      ORDER BY count DESC
      LIMIT 50
      """

      # Warmup
      IO.puts("\n🔥 Warming up cache...")
      warmup(conn, query_with_preagg, 3)
      warmup(conn, query_without_preagg, 3)

      IO.puts("\n📊 Running measurements (5 iterations each)...")

      # Run multiple iterations
      with_times =
        for i <- 1..5 do
          result = measure_full_path(conn, query_with_preagg, "CubeStore Direct")
          IO.puts("  Iteration #{i}: #{result.time_total}ms (query: #{result.time_query}ms, materialize: #{result.time_materialize}ms)")
          result
        end

      without_times =
        for i <- 1..5 do
          result = measure_full_path(conn, query_without_preagg, "HTTP Cached")
          IO.puts("  Iteration #{i}: #{result.time_total}ms (query: #{result.time_query}ms, materialize: #{result.time_materialize}ms)")
          result
        end

      # Calculate statistics
      avg_with_query = Enum.sum(Enum.map(with_times, & &1.time_query)) / 5
      avg_with_materialize = Enum.sum(Enum.map(with_times, & &1.time_materialize)) / 5
      avg_with_total = Enum.sum(Enum.map(with_times, & &1.time_total)) / 5

      avg_without_query = Enum.sum(Enum.map(without_times, & &1.time_query)) / 5
      avg_without_materialize = Enum.sum(Enum.map(without_times, & &1.time_materialize)) / 5
      avg_without_total = Enum.sum(Enum.map(without_times, & &1.time_total)) / 5

      IO.puts("\n" <> String.duplicate("-", 80))
      IO.puts("📈 RESULTS (averages over 5 iterations):")
      IO.puts(String.duplicate("-", 80))
      IO.puts("\nCubeStore Direct (WITH pre-agg):")
      IO.puts("  Query:         #{Float.round(avg_with_query, 1)}ms")
      IO.puts("  Materialization: #{Float.round(avg_with_materialize, 1)}ms")
      IO.puts("  TOTAL:         #{Float.round(avg_with_total, 1)}ms")
      IO.puts("  Rows:          #{hd(with_times).row_count}")

      IO.puts("\nHTTP API (WITHOUT pre-agg, cached):")
      IO.puts("  Query:         #{Float.round(avg_without_query, 1)}ms")
      IO.puts("  Materialization: #{Float.round(avg_without_materialize, 1)}ms")
      IO.puts("  TOTAL:         #{Float.round(avg_without_total, 1)}ms")
      IO.puts("  Rows:          #{hd(without_times).row_count}")

      speedup = avg_without_total / avg_with_total

      IO.puts("\n" <> String.duplicate("-", 80))

      if avg_with_total < avg_without_total do
        IO.puts("✅ CubeStore Direct is #{Float.round(speedup, 2)}x FASTER (#{Float.round(avg_without_total - avg_with_total, 1)}ms saved)")
      else
        IO.puts("⚠️  HTTP is faster (CubeStore: #{Float.round(avg_with_total, 1)}ms vs HTTP: #{Float.round(avg_without_total, 1)}ms)")
      end

      IO.puts(String.duplicate("=", 80))
    end

    test "2. Medium aggregation (more measures)", %{conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 2: Medium Aggregation (All 6 measures from pre-agg)")
      IO.puts(String.duplicate("=", 80))

      query_with_preagg = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount,
        MEASURE(mandata_captate.tax_amount_sum) as tax_amount,
        MEASURE(mandata_captate.subtotal_amount_sum) as subtotal_amount,
        MEASURE(mandata_captate.delivery_subtotal_amount_sum) as delivery_amount,
        MEASURE(mandata_captate.discount_total_amount_sum) as discount_amount
      FROM mandata_captate
      GROUP BY 1, 2
      ORDER BY count DESC
      LIMIT 100
      """

      query_without_preagg = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.email,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      GROUP BY 1, 2
      ORDER BY count DESC
      LIMIT 100
      """

      IO.puts("\n🔥 Warming up...")
      warmup(conn, query_with_preagg, 2)
      warmup(conn, query_without_preagg, 2)

      IO.puts("\n📊 Running measurements (3 iterations each)...")

      with_results =
        for i <- 1..3 do
          result = measure_full_path(conn, query_with_preagg, "CubeStore Direct")
          IO.puts("  CubeStore #{i}: #{result.time_total}ms total (#{result.time_query}ms query + #{result.time_materialize}ms materialize)")
          result
        end

      without_results =
        for i <- 1..3 do
          result = measure_full_path(conn, query_without_preagg, "HTTP Cached")
          IO.puts("  HTTP #{i}: #{result.time_total}ms total (#{result.time_query}ms query + #{result.time_materialize}ms materialize)")
          result
        end

      avg_with = Enum.sum(Enum.map(with_results, & &1.time_total)) / 3
      avg_without = Enum.sum(Enum.map(without_results, & &1.time_total)) / 3

      IO.puts("\n📈 Average Total Time:")
      IO.puts("  CubeStore Direct: #{Float.round(avg_with, 1)}ms")
      IO.puts("  HTTP Cached:      #{Float.round(avg_without, 1)}ms")

      if avg_with < avg_without do
        speedup = avg_without / avg_with
        IO.puts("  ✅ CubeStore #{Float.round(speedup, 2)}x faster!")
      end
    end

    test "3. Larger result set (500 rows)", %{conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 3: Larger Result Set (500 rows)")
      IO.puts(String.duplicate("=", 80))

      query_with_preagg = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      GROUP BY 1, 2
      ORDER BY count DESC
      LIMIT 500
      """

      query_without_preagg = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.email,
        MEASURE(mandata_captate.count) as count
      FROM mandata_captate
      GROUP BY 1, 2
      ORDER BY count DESC
      LIMIT 500
      """

      IO.puts("\n🔥 Warming up...")
      warmup(conn, query_with_preagg)
      warmup(conn, query_without_preagg)

      IO.puts("\n📊 Measuring...")

      with_result = measure_full_path(conn, query_with_preagg, "CubeStore Direct")
      without_result = measure_full_path(conn, query_without_preagg, "HTTP Cached")

      IO.puts("\nCubeStore Direct (#{with_result.row_count} rows):")
      IO.puts("  Query:         #{with_result.time_query}ms")
      IO.puts("  Materialize:   #{with_result.time_materialize}ms")
      IO.puts("  TOTAL:         #{with_result.time_total}ms")

      IO.puts("\nHTTP Cached (#{without_result.row_count} rows):")
      IO.puts("  Query:         #{without_result.time_query}ms")
      IO.puts("  Materialize:   #{without_result.time_materialize}ms")
      IO.puts("  TOTAL:         #{without_result.time_total}ms")

      if with_result.time_total < without_result.time_total do
        speedup = without_result.time_total / with_result.time_total
        IO.puts("\n✅ CubeStore #{Float.round(speedup, 2)}x faster!")
      end
    end

    test "4. Simple count query", %{conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 4: Simple Count Query")
      IO.puts(String.duplicate("=", 80))

      query_with_preagg = """
      SELECT
        MEASURE(mandata_captate.count) as total_count
      FROM mandata_captate
      """

      query_without_preagg = """
      SELECT
        mandata_captate.email,
        MEASURE(mandata_captate.count) as count
      FROM mandata_captate
      GROUP BY 1
      LIMIT 1
      """

      warmup(conn, query_with_preagg)
      warmup(conn, query_without_preagg)

      with_result = measure_full_path(conn, query_with_preagg, "CubeStore Direct")
      without_result = measure_full_path(conn, query_without_preagg, "HTTP Cached")

      IO.puts("\n📊 Results:")
      IO.puts("  CubeStore Direct: #{with_result.time_total}ms total")
      IO.puts("  HTTP Cached:      #{without_result.time_total}ms total")

      if with_result.time_total < without_result.time_total do
        IO.puts("  ✅ CubeStore faster by #{without_result.time_total - with_result.time_total}ms")
      end
    end

    test "5. Query breakdown analysis", %{conn: conn} do
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("TEST 5: Query vs Materialization Time Breakdown")
      IO.puts(String.duplicate("=", 80))

      query = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      GROUP BY 1, 2
      ORDER BY count DESC
      LIMIT 200
      """

      warmup(conn, query, 3)

      IO.puts("\n📊 Analyzing time distribution (5 runs)...")

      results =
        for i <- 1..5 do
          result = measure_full_path(conn, query, "CubeStore Direct")

          query_pct = Float.round(result.time_query / result.time_total * 100, 1)
          mat_pct = Float.round(result.time_materialize / result.time_total * 100, 1)

          IO.puts("  Run #{i}: #{result.time_total}ms (query: #{result.time_query}ms [#{query_pct}%], materialize: #{result.time_materialize}ms [#{mat_pct}%])")
          result
        end

      avg_query = Enum.sum(Enum.map(results, & &1.time_query)) / 5
      avg_materialize = Enum.sum(Enum.map(results, & &1.time_materialize)) / 5
      avg_total = Enum.sum(Enum.map(results, & &1.time_total)) / 5

      query_pct = Float.round(avg_query / avg_total * 100, 1)
      mat_pct = Float.round(avg_materialize / avg_total * 100, 1)

      IO.puts("\n📈 Average Breakdown:")
      IO.puts("  Query execution:    #{Float.round(avg_query, 1)}ms (#{query_pct}%)")
      IO.puts("  DataFrame materialize: #{Float.round(avg_materialize, 1)}ms (#{mat_pct}%)")
      IO.puts("  TOTAL:              #{Float.round(avg_total, 1)}ms (100%)")
      IO.puts("\n💡 Insight: Materialization overhead is #{Float.round(avg_materialize, 1)}ms regardless of data source")
    end
  end
end
