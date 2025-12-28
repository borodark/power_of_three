defmodule PowerOfThree.CubeFrameAdbcTest do
  use ExUnit.Case, async: false

  alias PowerOfThree.{CubeConnection, CubeFrame, DimensionRef, MeasureRef}

  @moduletag :live_cube

  setup_all do
    # Find the Cube ADBC driver
    driver_path =
      "_build/test/lib/adbc/priv/lib/libadbc_driver_cube.so"
      |> Path.expand()

    # Connect to live Cube ADBC endpoint on port 8120
    {:ok, conn} =
      CubeConnection.connect(
        host: "localhost",
        port: 8120,
        token: "test",
        driver_path: driver_path
      )

    on_exit(fn ->
      CubeConnection.disconnect(conn)
    end)

    {:ok, conn: conn}
  end

  describe "from_query/4 with raw SQL" do
    test "queries orders_no_preagg cube", %{conn: conn} do
      sql =
        "SELECT market_code, brand_code, COUNT(*) as count FROM orders_no_preagg GROUP BY market_code, brand_code LIMIT 5"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      assert %Explorer.DataFrame{} = df
      Explorer.DataFrame.print(df)

      # Verify shape
      {rows, cols} = Explorer.DataFrame.shape(df)
      assert rows <= 5
      assert cols == 3

      # Verify columns exist
      column_names = Explorer.DataFrame.names(df)
      assert "market_code" in column_names
      assert "brand_code" in column_names
      assert "count" in column_names
    end

    test "queries orders_with_preagg cube", %{conn: conn} do
      sql =
        "SELECT market_code, brand_code, COUNT(*) as count FROM orders_with_preagg GROUP BY market_code, brand_code LIMIT 5"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      assert %Explorer.DataFrame{} = df
      Explorer.DataFrame.print(df)

      # Verify shape
      {rows, cols} = Explorer.DataFrame.shape(df)
      assert rows <= 5
      assert cols == 3
    end

    test "handles simple SELECT *", %{conn: conn} do
      sql = "SELECT * FROM orders_no_preagg LIMIT 3"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      assert %Explorer.DataFrame{} = df

      {rows, _cols} = Explorer.DataFrame.shape(df)
      assert rows <= 3
    end

    test "handles WHERE clauses", %{conn: conn} do
      sql =
        "SELECT market_code, COUNT(*) as count FROM orders_no_preagg WHERE market_code = 'US' GROUP BY market_code"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      assert %Explorer.DataFrame{} = df

      # All rows should have market_code = 'US'
      market_codes = Explorer.DataFrame.to_columns(df)["market_code"]
      assert Enum.all?(market_codes, &(&1 == "US"))
    end

    test "handles ORDER BY", %{conn: conn} do
      sql =
        "SELECT brand_code, COUNT(*) as count FROM orders_no_preagg GROUP BY brand_code ORDER BY count DESC LIMIT 5"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      assert %Explorer.DataFrame{} = df

      # Verify counts are in descending order
      counts = Explorer.DataFrame.to_columns(df)["count"]
      assert counts == Enum.sort(counts, :desc)
    end
  end

  describe "from_query!/4 with raw SQL" do
    test "returns DataFrame on success", %{conn: conn} do
      sql = "SELECT * FROM orders_no_preagg LIMIT 2"

      df = CubeFrame.from_query!(conn, sql)
      assert %Explorer.DataFrame{} = df

      {rows, _cols} = Explorer.DataFrame.shape(df)
      assert rows <= 2
    end

    test "raises on invalid SQL", %{conn: conn} do
      sql = "SELECT * FROM nonexistent_table"

      assert_raise Adbc.Error, fn ->
        CubeFrame.from_query!(conn, sql)
      end
    end
  end

  describe "PowerOfThree query options to Cube query translation" do
    test "converts dimensions and measures correctly" do
      query_opts = [
        columns: [
          %DimensionRef{
            name: :market_code,
            sql: "market_code",
            type: :string,
            module: Order
          },
          %MeasureRef{
            name: :count,
            type: :count,
            module: Order
          }
        ],
        limit: 5
      ]

      {:ok, cube_query} = PowerOfThree.CubeSqlGenerator.to_cube_query(query_opts)

      assert cube_query["dimensions"] == ["mandata_captate.market_code"]
      assert cube_query["measures"] == ["mandata_captate.count"]
      assert cube_query["limit"] == 5
    end

    test "converts WHERE clause to filters" do
      query_opts = [
        columns: [
          %DimensionRef{
            name: :market_code,
            sql: "market_code",
            type: :string,
            module: Order
          },
          %MeasureRef{
            name: :count,
            type: :count,
            module: Order
          }
        ],
        where: [
          {%DimensionRef{
             name: :market_code,
             sql: "market_code",
             type: :string,
             module: Order
           }, :==, "US"}
        ],
        limit: 5
      ]

      {:ok, cube_query} = PowerOfThree.CubeSqlGenerator.to_cube_query(query_opts)

      assert cube_query["dimensions"] == ["mandata_captate.market_code"]
      assert cube_query["measures"] == ["mandata_captate.count"]
      assert cube_query["limit"] == 5
      # Verify filters were added
      assert is_list(cube_query["filters"])
      assert length(cube_query["filters"]) > 0
      [filter | _] = cube_query["filters"]
      assert filter["member"] == "mandata_captate.market_code"
      assert filter["operator"] == "equals"
      assert filter["values"] == ["US"]
    end

    test "converts ORDER BY to order format" do
      query_opts = [
        columns: [
          %DimensionRef{
            name: :brand_code,
            sql: "brand_code",
            type: :string,
            module: Order
          },
          %MeasureRef{
            name: :count,
            type: :count,
            module: Order
          }
        ],
        order_by: [{2, :desc}],
        limit: 5
      ]

      {:ok, cube_query} = PowerOfThree.CubeSqlGenerator.to_cube_query(query_opts)

      assert cube_query["dimensions"] == ["mandata_captate.brand_code"]
      assert cube_query["measures"] == ["mandata_captate.count"]
      assert cube_query["limit"] == 5
      # Verify order was added
      assert cube_query["order"] == [["mandata_captate.count", "desc"]]
    end
  end

  describe "Direct SQL generation for ADBC" do
    test "converts PowerOfThree query options to Cube query format" do
      query_opts = [
        columns: [
          %DimensionRef{
            name: :market_code,
            sql: "market_code",
            type: :string,
            module: Order
          },
          %DimensionRef{
            name: :brand_code,
            sql: "brand_code",
            type: :string,
            module: Order
          },
          %MeasureRef{
            name: :count,
            type: :count,
            module: Order
          }
        ],
        limit: 5
      ]

      {:ok, cube_query} = PowerOfThree.CubeSqlGenerator.to_cube_query(query_opts)

      assert cube_query["dimensions"] == [
               "mandata_captate.market_code",
               "mandata_captate.brand_code"
             ]

      assert cube_query["measures"] == ["mandata_captate.count"]
      assert cube_query["limit"] == 5
    end

    test "generates SQL with cube names (not pre-agg tables)" do
      query_opts = [
        columns: [
          %DimensionRef{
            name: :market_code,
            sql: "market_code",
            type: :string,
            module: Order
          },
          %MeasureRef{
            name: :count,
            type: :count,
            module: Order
          }
        ],
        limit: 10
      ]

      {:ok, sql} = PowerOfThree.CubeSqlGenerator.generate_sql(query_opts)

      assert is_binary(sql)
      # Should reference cube name
      assert sql =~ "FROM mandata_captate"
      # Should have SELECT with column aliases
      assert sql =~ "SELECT"
      assert sql =~ "market_code as market_code"
      assert sql =~ "COUNT(*) as count"
      # Should have GROUP BY for dimension
      assert sql =~ "GROUP BY market_code"
      assert sql =~ "LIMIT 10"

      # Should NOT contain pre-aggregation table references
      refute sql =~ "dev_pre_aggregations"
    end

    test "handles WHERE clause in generated SQL" do
      query_opts = [
        columns: [
          %DimensionRef{
            name: :market_code,
            sql: "market_code",
            type: :string,
            module: Order
          },
          %MeasureRef{
            name: :count,
            type: :count,
            module: Order
          }
        ],
        where: [
          {%DimensionRef{
             name: :market_code,
             sql: "market_code",
             type: :string,
             module: Order
           }, :==, "US"}
        ],
        limit: 10
      ]

      {:ok, sql} = PowerOfThree.CubeSqlGenerator.generate_sql(query_opts)

      assert is_binary(sql)
      assert sql =~ "FROM mandata_captate"
      assert sql =~ "WHERE market_code = 'US'"
      assert sql =~ "GROUP BY market_code"
      assert sql =~ "LIMIT 10"
    end
  end

  describe "aggregations" do
    test "COUNT works correctly", %{conn: conn} do
      sql = "SELECT COUNT(*) as total FROM orders_no_preagg"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      columns = Explorer.DataFrame.to_columns(df)
      assert is_integer(hd(columns["total"]))
      assert hd(columns["total"]) > 0
    end

    test "SUM works correctly", %{conn: conn} do
      sql = "SELECT SUM(total_amount_sum) as total FROM orders_no_preagg"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      columns = Explorer.DataFrame.to_columns(df)
      assert is_number(hd(columns["total"]))
    end

    test "COUNT DISTINCT works correctly", %{conn: conn} do
      # Use the customer_id_distinct measure which is defined in the cube
      sql = "SELECT customer_id_distinct FROM orders_no_preagg LIMIT 1"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      columns = Explorer.DataFrame.to_columns(df)
      assert is_integer(hd(columns["customer_id_distinct"]))
      assert hd(columns["customer_id_distinct"]) > 0
    end
  end

  describe "GROUP BY queries" do
    test "groups by single dimension", %{conn: conn} do
      sql = "SELECT market_code, COUNT(*) as count FROM orders_no_preagg GROUP BY market_code"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      assert %Explorer.DataFrame{} = df

      columns = Explorer.DataFrame.to_columns(df)
      # Should have unique market codes
      market_codes = columns["market_code"]
      assert length(Enum.uniq(market_codes)) == length(market_codes)
    end

    test "groups by multiple dimensions", %{conn: conn} do
      sql =
        "SELECT market_code, brand_code, COUNT(*) as count FROM orders_no_preagg GROUP BY market_code, brand_code LIMIT 10"

      assert {:ok, df} = CubeFrame.from_query(conn, sql)
      {rows, cols} = Explorer.DataFrame.shape(df)
      assert rows <= 10
      assert cols == 3
    end
  end

  describe "error handling" do
    test "returns error tuple for invalid SQL", %{conn: conn} do
      sql = "SELECT * FROM nonexistent_cube"

      assert {:error, _reason} = CubeFrame.from_query(conn, sql)
    end

    test "returns error tuple for malformed SQL", %{conn: conn} do
      sql = "INVALID SQL QUERY"

      assert {:error, _reason} = CubeFrame.from_query(conn, sql)
    end
  end
end
