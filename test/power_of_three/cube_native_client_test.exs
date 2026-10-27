defmodule PowerOfThree.CubeNativeClientTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.{CubeFrame, CubeNativeClient}
  alias PowerOfThree.CubeNative.Protocol
  alias PowerOfThree.CubeNativeFakeServer, as: FakeServer
  alias Explorer.DataFrame, as: DF

  defp batch1, do: DF.new(brand: ["a", "b", "c"], count: [1, 2, 3])
  defp batch2, do: DF.new(brand: ["d", "e"], count: [4, 5])

  defp connect(respond, opts \\ []) do
    port = FakeServer.start(respond)
    CubeNativeClient.connect(Keyword.merge([port: port, token: "test"], opts))
  end

  describe "protocol" do
    test "round-trips client messages" do
      for msg <- [
            {:handshake_request, 1},
            {:auth_request, "tok", nil},
            {:auth_request, "tok", "db"},
            {:query_request, "SELECT 1"}
          ] do
        assert {:ok, ^msg} =
                 msg |> Protocol.encode() |> IO.iodata_to_binary() |> Protocol.decode()
      end
    end

    test "matches the byte layout in protocol.rs" do
      assert IO.iodata_to_binary(Protocol.encode({:query_request, "SELECT"})) ==
               <<0x10, 0, 0, 0, 6, "SELECT">>
    end
  end

  test "handshake and auth" do
    assert {:ok, client} = connect(fn _ -> [batch1()] end)
    assert client.server_version == "fake"
    assert client.session_id == "session-1"
  end

  test "bad token is reported" do
    assert {:error, {:auth_failed, "bad token"}} = connect(fn _ -> [] end, token: "nope")
  end

  test "multi-batch result becomes one DataFrame" do
    {:ok, client} = connect(fn _ -> [batch1(), batch2()] end)
    assert {:ok, df} = CubeNativeClient.query_df(client, "SELECT brand, count FROM x")
    assert DF.names(df) == ["brand", "count"]
    assert DF.to_columns(df, atom_keys: true).count == [1, 2, 3, 4, 5]
  end

  test "server error comes back as {:server, code, message}" do
    {:ok, client} = connect(fn _ -> {:error, "QUERY_ERROR", "no such cube"} end)

    assert {:error, {:server, "QUERY_ERROR", "no such cube"}} =
             CubeNativeClient.query(client, "SELECT nope")
  end

  test "CubeFrame.from_query/4 accepts a native client" do
    {:ok, client} = connect(fn _ -> [batch1()] end)
    assert {:ok, df} = CubeFrame.from_query(client, "SELECT brand, count FROM x")
    assert DF.n_rows(df) == 3

    assert {:error, :params_not_supported_by_native_transport} =
             CubeFrame.from_query(client, "SELECT ?", [1])
  end
end

defmodule PowerOfThree.CubeNativeClientLiveTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.{CubeFrame, CubeNativeClient}

  @moduletag :live_cube
  @moduletag :native

  setup_all do
    {:ok, client} = CubeNativeClient.connect(host: "localhost", port: 8120, token: "test")
    on_exit(fn -> CubeNativeClient.close(client) end)
    {:ok, client: client}
  end

  test "raw SQL over the native client", %{client: client} do
    sql =
      "SELECT market_code, brand_code, COUNT(*) as count FROM orders_no_preagg GROUP BY market_code, brand_code LIMIT 5"

    assert {:ok, df} = CubeFrame.from_query(client, sql)
    assert Explorer.DataFrame.n_rows(df) == 5
    assert "count" in Explorer.DataFrame.names(df)
  end

  test "df/1 with connection_type: :native" do
    assert {:ok, df} =
             Customer.df(
               columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
               limit: 5,
               connection_type: :native,
               connection_opts: [token: "test"],
               cube_opts: [host: "localhost", port: 4008, token: "test"]
             )

    assert Explorer.DataFrame.names(df) == ["brand", "count"]
    assert Explorer.DataFrame.n_rows(df) == 5
  end

  test "df/1 reusing a native client as :connection", %{client: client} do
    assert {:ok, df} =
             Customer.df(
               columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
               limit: 3,
               connection: client,
               cube_opts: [host: "localhost", port: 4008, token: "test"]
             )

    assert Explorer.DataFrame.n_rows(df) == 3
  end
end

defmodule PowerOfThree.CubeNativeDfTest do
  use ExUnit.Case, async: true

  test "connection_type: :adbc raises with a pointer to :native" do
    assert_raise ArgumentError, ~r/connection_type: :native/, fn ->
      Customer.df(columns: [Customer.Measures.count()], connection_type: :adbc)
    end
  end

  test "df!/1 raises a readable error when the native client fails" do
    # Nothing listens on port 1, so connect fails with {:error, :econnrefused}.
    assert_raise RuntimeError, ~r/Cube query failed/, fn ->
      Customer.df!(
        columns: [Customer.Measures.count()],
        connection_type: :native,
        connection_opts: [port: 1, token: "test"],
        cube_opts: [host: "localhost", port: 1, token: "test"]
      )
    end
  end
end

defmodule PowerOfThree.CubeSqlGeneratorMemberNamesTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.CubeSqlGenerator

  # cubesql exposes cube members, not table columns: brand is defined as
  # `sql: brand_code`, but SQL against power_customers must say `brand`.
  test "dimensions use member names, measures use MEASURE()" do
    {:ok, sql} =
      CubeSqlGenerator.generate_sql(
        cube: "power_customers",
        columns: [Customer.Dimensions.brand(), Customer.Measures.count()],
        limit: 5
      )

    assert sql ==
             "SELECT brand as brand, MEASURE(count) as count FROM power_customers GROUP BY brand LIMIT 5"
  end

  test "dimensions with custom SQL are referenced by member name" do
    {:ok, sql} =
      CubeSqlGenerator.generate_sql(
        cube: "power_customers",
        columns: [Customer.Dimensions.zodiac(), Customer.Measures.count()]
      )

    refute sql =~ "CASE"
    assert sql =~ "SELECT zodiac as zodiac, MEASURE(count) as count"
  end
end
