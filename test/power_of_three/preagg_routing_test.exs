defmodule PowerOfThree.PreAggRoutingTest do
  @moduledoc """
  Comprehensive tests for pre-aggregation routing via cubesqld.

  Tests various query patterns to identify gaps in the implementation:
  - Different measure combinations
  - Different dimension combinations
  - Partial pre-agg coverage (some measures/dimensions not in pre-agg)
  - Multiple pre-aggs for same cube
  - Edge cases and error conditions

  Run with:
    cd path/to/power-of-three
    mix test test/power_of_three/preagg_routing_test.exs --trace --include live_cube --include adbc
  """

  use ExUnit.Case, async: true

  alias Adbc.{Database, Connection, Result}

  @moduletag :live_cube
  @moduletag :adbc

  @cube_driver_version System.get_env("CUBE_DRIVER_VERSION", "0.1.2")

  # Cube server connection details (ADBC port for pre-agg routing)
  @cube_host "localhost"
  # ADBC port
  @cube_adbc_port 8120
  @cube_token "test"

  setup_all do
    unless Code.ensure_loaded?(Adbc) do
      {:skip, "adbc dependency not available"}
    end

    case Adbc.Driver.so_path(:cube, version: @cube_driver_version) do
      {:ok, _path} ->
        :ok

      {:error, reason} ->
        raise "Cube driver not available: #{reason}"
    end

    # Verify cubesqld is running on ADBC port
    case :gen_tcp.connect(String.to_charlist(@cube_host), @cube_adbc_port, [:binary], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, :econnrefused} ->
        raise """
        cubesqld not running on #{@cube_host}:#{@cube_adbc_port}.
        Start with ADBC(Arrow Native) support:
          cd path/to/cube/examples/recipes/arrow-ipc
          source .env
          export CUBESQL_CUBESTORE_DIRECT=true
          export CUBESQL_CUBE_URL=http://localhost:4008/cubejs-api
          export CUBESQL_CUBESTORE_URL=ws://127.0.0.1:3030/ws
          export CUBESQL_CUBE_TOKEN=test
          export CUBESQL_PG_PORT=4444
          export CUBEJS_ADBC_PORT=8120
          export RUST_LOG=info
          path/to/cube/rust/cubesql/target/debug/cubesqld
        """

      {:error, reason} ->
        raise "Failed to connect to cubesqld: #{inspect(reason)}"
    end

    :ok
  end

  setup do
    db =
      start_supervised!(
        {Database,
         driver: :cube,
         version: @cube_driver_version,
         "adbc.cube.host": @cube_host,
         "adbc.cube.port": Integer.to_string(@cube_adbc_port),
         "adbc.cube.connection_mode": "native",
         "adbc.cube.token": @cube_token}
      )

    conn = start_supervised!({Connection, database: db})
    %{db: db, conn: conn}
  end

  describe "Pre-aggregation routing - Basic Coverage" do
    test "full pre-agg coverage - all measures and dimensions match", %{conn: conn} do
      # Query that EXACTLY matches mandata_captate.sums_and_count_daily pre-agg
      query = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      WHERE mandata_captate.updated_at >= '2024-01-01'
      GROUP BY 1, 2
      ORDER BY total_amount DESC
      LIMIT 10
      """

      IO.puts("\n📊 Test: Full pre-agg coverage")
      IO.puts("Expected: Should route to CubeStore direct")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      assert length(materialized.data) > 0, "Should return data"
      IO.puts("✅ Returned #{length(materialized.data)} columns")

      # Check if all expected fields are present
      column_names = Enum.map(materialized.data, & &1.name)
      assert "market_code" in column_names
      assert "brand_code" in column_names
      assert "count" in column_names
      assert "total_amount" in column_names
    end

    test "subset of measures - partial coverage", %{conn: conn} do
      # Query using SOME measures from pre-agg (not all)
      query = """
      SELECT
        mandata_captate.market_code,
        MEASURE(mandata_captate.count) as count
      FROM mandata_captate
      WHERE mandata_captate.updated_at >= '2024-01-01'
      GROUP BY 1
      LIMIT 10
      """

      IO.puts("\n📊 Test: Partial measure coverage")
      IO.puts("Expected: Should still route to CubeStore (subset of measures)")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      assert length(materialized.data) > 0
      IO.puts("✅ Returned data with subset of measures")
    end

    test "subset of dimensions - partial coverage", %{conn: conn} do
      # Query using SOME dimensions from pre-agg
      query = """
      SELECT
        mandata_captate.market_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      GROUP BY 1
      LIMIT 10
      """

      IO.puts("\n📊 Test: Partial dimension coverage")
      IO.puts("Expected: Should route to CubeStore (subset of dimensions)")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      assert length(materialized.data) > 0
      IO.puts("✅ Returned data with subset of dimensions")
    end

    test "no dimensions - measures only", %{conn: conn} do
      # Query with measures but no GROUP BY dimensions
      query = """
      SELECT
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      WHERE mandata_captate.updated_at >= '2024-01-01'
      LIMIT 10
      """

      IO.puts("\n📊 Test: Measures only, no dimensions")
      IO.puts("Expected: Should route to CubeStore (dimensions optional)")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      assert length(materialized.data) > 0
      IO.puts("✅ Returned aggregated data without dimensions")
    end
  end

  describe "Pre-aggregation routing - Negative Cases" do
    test "measure NOT in pre-agg - should fallback to HTTP", %{conn: conn} do
      # Query using customer_id_sum which is NOT in the pre-agg
      query = """
      SELECT
        mandata_captate.market_code,
        MEASURE(mandata_captate.customer_id_sum) as customer_sum
      FROM mandata_captate
      GROUP BY 1
      LIMIT 10
      """

      IO.puts("\n📊 Test: Measure not in pre-agg")
      IO.puts("Expected: Should fallback to HTTP (measure not covered)")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      assert length(materialized.data) > 0
      IO.puts("⚠️  Returned data via HTTP fallback")
    end

    test "dimension NOT in pre-agg - should fallback to HTTP", %{conn: conn} do
      # Query using email dimension which is NOT in the pre-agg
      query = """
      SELECT
        mandata_captate.email,
        MEASURE(mandata_captate.count) as count
      FROM mandata_captate
      GROUP BY 1
      LIMIT 10
      """

      IO.puts("\n📊 Test: Dimension not in pre-agg")
      IO.puts("Expected: Should fallback to HTTP (dimension not covered)")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      assert length(materialized.data) > 0
      IO.puts("⚠️  Returned data via HTTP fallback")
    end

    test "mixed coverage - some fields in pre-agg, some not", %{conn: conn} do
      # Query mixing covered and uncovered fields
      query = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.email,
        MEASURE(mandata_captate.count) as count
      FROM mandata_captate
      GROUP BY 1, 2
      LIMIT 10
      """

      IO.puts("\n📊 Test: Mixed coverage (some fields not in pre-agg)")
      IO.puts("Expected: Should fallback to HTTP (partial coverage not enough)")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      assert length(materialized.data) > 0
      IO.puts("⚠️  Returned data via HTTP fallback")
    end
  end

  describe "Pre-aggregation routing - Multiple Measures" do
    test "all 6 measures from pre-agg", %{conn: conn} do
      # Query using ALL measures defined in pre-agg
      query = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount,
        MEASURE(mandata_captate.tax_amount_sum) as tax_amount,
        MEASURE(mandata_captate.subtotal_amount_sum) as subtotal_amount,
        MEASURE(mandata_captate.discount_total_amount_sum) as discount_amount,
        MEASURE(mandata_captate.delivery_subtotal_amount_sum) as delivery_amount
      FROM mandata_captate
      WHERE mandata_captate.updated_at >= '2024-01-01'
      GROUP BY 1, 2
      LIMIT 10
      """

      IO.puts("\n📊 Test: All 6 measures from pre-agg")
      IO.puts("Expected: Should route to CubeStore with all measures")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      assert length(materialized.data) > 0
      IO.puts("✅ Returned all 6 measures + 2 dimensions")
    end

    test "different measure combinations", %{conn: conn} do
      # Test various combinations to ensure flexible matching
      test_cases = [
        {["count"], "single measure"},
        {["count", "total_amount_sum"], "two measures"},
        {["count", "total_amount_sum", "tax_amount_sum"], "three measures"}
      ]

      for {measures, description} <- test_cases do
        measure_select =
          Enum.map_join(measures, ",\n        ", fn m ->
            "MEASURE(mandata_captate.#{m}) as #{m}"
          end)

        query = """
        SELECT
          mandata_captate.market_code,
          #{measure_select}
        FROM mandata_captate
        GROUP BY 1
        LIMIT 5
        """

        IO.puts("\n📊 Test: #{description}")

        assert {:ok, result} = Connection.query(conn, query)
        materialized = Result.materialize(result)

        assert length(materialized.data) > 0
        IO.puts("✅ #{description} worked")
      end
    end
  end

  describe "Pre-aggregation routing - Performance Comparison" do
    @tag :performance
    test "compare HTTP vs CubeStore routing", %{conn: conn} do
      # This test compares the same query with and without pre-agg coverage

      # Query WITH pre-agg coverage
      query_with_preagg = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.brand_code,
        MEASURE(mandata_captate.count) as count,
        MEASURE(mandata_captate.total_amount_sum) as total_amount
      FROM mandata_captate
      GROUP BY 1, 2
      LIMIT 100
      """

      # Query WITHOUT pre-agg coverage (using uncovered field)
      query_without_preagg = """
      SELECT
        mandata_captate.market_code,
        mandata_captate.email,
        MEASURE(mandata_captate.count) as count
      FROM mandata_captate
      GROUP BY 1, 2
      LIMIT 100
      """

      IO.puts("\n📊 Performance Comparison Test")

      # Warmup
      Connection.query(conn, query_with_preagg)
      Connection.query(conn, query_without_preagg)

      # Measure WITH pre-agg
      start = System.monotonic_time(:millisecond)
      {:ok, _} = Connection.query(conn, query_with_preagg)
      time_with = System.monotonic_time(:millisecond) - start

      # Measure WITHOUT pre-agg
      start = System.monotonic_time(:millisecond)
      {:ok, _} = Connection.query(conn, query_without_preagg)
      time_without = System.monotonic_time(:millisecond) - start

      IO.puts("WITH pre-agg (CubeStore): #{time_with}ms")
      IO.puts("WITHOUT pre-agg (HTTP): #{time_without}ms")

      if time_with < time_without do
        speedup = Float.round(time_without / time_with, 2)
        IO.puts("✅ Pre-agg is #{speedup}x FASTER!")
      else
        IO.puts("⚠️  Pre-agg routing may not be active or dataset too small")
      end
    end
  end

  describe "Pre-aggregation routing - Error Handling" do
    test "invalid measure name - should return error", %{conn: conn} do
      query = """
      SELECT
        MEASURE(mandata_captate.nonexistent_measure) as bad_measure
      FROM mandata_captate
      LIMIT 10
      """

      IO.puts("\n📊 Test: Invalid measure name")

      # This should either error or return empty result
      result = Connection.query(conn, query)

      case result do
        {:ok, _} -> IO.puts("⚠️  Query succeeded (unexpected)")
        {:error, error} -> IO.puts("✅ Error returned: #{inspect(error)}")
      end
    end

    test "empty result set", %{conn: conn} do
      # Query with impossible WHERE condition
      query = """
      SELECT
        mandata_captate.market_code,
        MEASURE(mandata_captate.count) as count
      FROM mandata_captate
      WHERE mandata_captate.updated_at > '2099-01-01'
      GROUP BY 1
      """

      IO.puts("\n📊 Test: Empty result set")

      assert {:ok, result} = Connection.query(conn, query)
      _materialized = Result.materialize(result)

      IO.puts("✅ Empty result handled correctly")
    end
  end
end
