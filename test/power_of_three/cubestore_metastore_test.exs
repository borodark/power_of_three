defmodule PowerOfThree.CubeStoreMetastoreTest do
  @moduledoc """
  Tests CubeStore metastore queries to discover pre-aggregation table names.

  This test verifies we can query the system.tables to find pre-aggregation tables
  that are stored in CubeStore. This is the KEY to routing queries directly to
  CubeStore - we need to know the actual table names.

  Run with:
    cd ~/projects/learn_erl/power-of-three
    mix test test/power_of_three/cubestore_metastore_test.exs --trace
  """

  use ExUnit.Case, async: false

  alias Adbc.{Database, Connection, Result}

  # Path to Cube ADBC driver
  @cube_driver_path Path.join(:code.priv_dir(:adbc), "lib/libadbc_driver_cube.so")

  # Cube server connection details
  @cube_host "localhost"
  # ADBC port
  @cube_adbc_port 8120
  @cube_token "test"

  setup_all do
    unless File.exists?(@cube_driver_path) do
      raise "Cube driver not found at #{@cube_driver_path}"
    end

    # Verify cubesqld is running on ADBC port
    case :gen_tcp.connect(String.to_charlist(@cube_host), @cube_adbc_port, [:binary], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, :econnrefused} ->
        raise """
        cubesqld not running on #{@cube_host}:#{@cube_adbc_port}.
        Start with:
          cd ~/projects/learn_erl/cube/examples/recipes/arrow-ipc
          source .env
          ~/projects/learn_erl/cube/rust/cubesql/target/debug/cubesqld
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
         driver: @cube_driver_path,
         "adbc.cube.host": @cube_host,
         "adbc.cube.port": Integer.to_string(@cube_adbc_port),
         "adbc.cube.connection_mode": "native",
         "adbc.cube.token": @cube_token}
      )

    conn = start_supervised!({Connection, database: db})
    %{db: db, conn: conn}
  end

  describe "CubeStore metastore access via system.tables" do
    test "query all tables from CubeStore metastore", %{conn: conn} do
      # This queries the RocksDB metastore via system.tables
      query = """
      SELECT
        table_schema,
        table_name,
        is_ready,
        has_data,
        sealed
      FROM system.tables
      ORDER BY table_schema, table_name
      """

      IO.puts("\n🔍 Querying CubeStore metastore (system.tables)...")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      # Should return columns
      column_names = Enum.map(materialized.data, & &1.name)
      assert "table_schema" in column_names
      assert "table_name" in column_names
      assert "is_ready" in column_names
      assert "has_data" in column_names

      IO.puts("\n📊 Tables found in CubeStore metastore:")
      IO.puts("=" |> String.duplicate(80))

      if length(materialized.data) > 0 do
        # Print table information
        print_table_results(materialized)
      else
        IO.puts("⚠️  No tables found in metastore")
      end
    end

    test "filter pre-aggregation tables specifically", %{conn: conn} do
      # Pre-aggregation tables typically have specific naming patterns
      # Let's query for tables that match common pre-agg patterns
      query = """
      SELECT
        table_schema,
        table_name,
        is_ready,
        has_data
      FROM system.tables
      WHERE
        -- Pre-aggregations are usually in specific schemas
        table_schema NOT IN ('information_schema', 'system', 'mysql')
        AND is_ready = true
      ORDER BY table_name
      """

      IO.puts("\n🎯 Filtering for pre-aggregation tables...")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      IO.puts("\n📊 Pre-aggregation tables:")
      IO.puts("=" |> String.duplicate(80))

      if length(materialized.data) > 0 do
        print_table_results(materialized)

        IO.puts("\n✅ Found #{count_rows(materialized)} pre-aggregation table(s)")
      else
        IO.puts("⚠️  No pre-aggregation tables found")
        IO.puts("This might mean:")
        IO.puts("  1. Pre-aggregations haven't been built yet")
        IO.puts("  2. The naming pattern is different")
        IO.puts("  3. They're stored in a different schema")
      end
    end

    test "discover mandata_captate pre-aggregation table name", %{conn: conn} do
      # Try to find the specific pre-agg table for mandata_captate
      query = """
      SELECT
        table_schema,
        table_name,
        is_ready,
        has_data,
        created_at
      FROM system.tables
      WHERE
        table_name LIKE '%mandata_captate%'
        OR table_name LIKE '%sums_and_count_daily%'
      ORDER BY created_at DESC
      """

      IO.puts("\n🔎 Searching for mandata_captate pre-aggregation...")

      assert {:ok, result} = Connection.query(conn, query)
      materialized = Result.materialize(result)

      IO.puts("\n📊 mandata_captate pre-aggregation tables:")
      IO.puts("=" |> String.duplicate(80))

      if length(materialized.data) > 0 do
        print_table_results(materialized)

        IO.puts("\n✅ This is the table name to use for direct CubeStore queries!")
      else
        IO.puts("⚠️  No mandata_captate pre-aggregation found")
        IO.puts("Trying broader search...")

        # Fallback: list ALL tables to see what's available
        fallback_query = "SELECT table_schema, table_name FROM system.tables"
        assert {:ok, fallback_result} = Connection.query(conn, fallback_query)
        fallback_materialized = Result.materialize(fallback_result)

        IO.puts("\nAll available tables:")
        print_table_results(fallback_materialized)
      end
    end
  end

  # Helper functions

  defp print_table_results(%Result{data: columns}) do
    # Get column names
    column_names = Enum.map(columns, & &1.name)

    # Get number of rows (from first column)
    num_rows =
      if length(columns) > 0 do
        hd(columns).data
        |> Adbc.Column.to_list()
        |> length()
      else
        0
      end

    if num_rows == 0 do
      IO.puts("(no rows)")
    else
      # Convert columns to list of rows
      rows =
        for i <- 0..(num_rows - 1) do
          Enum.map(columns, fn col ->
            col.data
            |> Adbc.Column.to_list()
            |> Enum.at(i)
            |> format_value()
          end)
        end

      # Print header
      IO.puts(Enum.join(column_names, " | "))
      IO.puts(String.duplicate("-", 80))

      # Print rows
      Enum.each(rows, fn row ->
        IO.puts(Enum.join(row, " | "))
      end)
    end
  end

  defp format_value(nil), do: "NULL"
  defp format_value(true), do: "true"
  defp format_value(false), do: "false"
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)

  defp count_rows(%Result{data: columns}) do
    if length(columns) > 0 do
      hd(columns).data
      |> Adbc.Column.to_list()
      |> length()
    else
      0
    end
  end
end
