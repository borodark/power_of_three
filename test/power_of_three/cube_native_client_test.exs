defmodule PowerOfThree.CubeNativeClientTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.{CubeFrame, CubeNativeClient}
  alias PowerOfThree.CubeNative.Protocol
  alias PowerOfThree.CubeNativeFakeServer, as: FakeServer
  alias Explorer.DataFrame, as: DF

  defp batch1, do: DF.new(brand: ["a", "b", "c"], count: [1, 2, 3])
  defp batch2, do: DF.new(brand: ["d", "e"], count: [4, 5])

  defp connect(respond, opts \\ [], server_opts \\ []) do
    port = FakeServer.start(respond, server_opts)
    CubeNativeClient.connect(Keyword.merge([port: port, token: "test"], opts))
  end

  describe "protocol" do
    test "round-trips client messages" do
      for msg <- [
            {:handshake_request, 2},
            {:auth_request, 1, nil, "tok", nil},
            {:auth_request, 1, nil, "tok", "db"},
            {:auth_request, 2, nil, "tok", nil},
            {:auth_request, 2, "cube", "tok", "db"},
            {:query_request, "SELECT 1"}
          ] do
        version = if(elem(msg, 0) == :auth_request, do: elem(msg, 1))

        assert {:ok, ^msg} =
                 msg |> Protocol.encode() |> IO.iodata_to_binary() |> Protocol.decode(version)
      end
    end

    test "matches the byte layout in protocol.rs" do
      assert IO.iodata_to_binary(Protocol.encode({:query_request, "SELECT"})) ==
               <<0x10, 0, 0, 0, 6, "SELECT">>

      # Version 1: password, optional database
      assert IO.iodata_to_binary(Protocol.encode({:auth_request, 1, nil, "pw", nil})) ==
               <<0x03, 0, 0, 0, 2, "pw", 0>>

      # Version 2: optional user first
      assert IO.iodata_to_binary(Protocol.encode({:auth_request, 2, "u", "pw", "db"})) ==
               <<0x03, 1, 0, 0, 0, 1, "u", 0, 0, 0, 2, "pw", 1, 0, 0, 0, 2, "db">>
    end
  end

  test "handshake and auth" do
    assert {:ok, client} = connect(fn _ -> [batch1()] end)
    assert client.server_version == "fake"
    assert client.protocol_version == 2
    assert client.session_id == "session-2"
  end

  test "version 2 sends the user" do
    assert {:ok, %{protocol_version: 2}} = connect(fn _ -> [] end, user: "cube")
    assert {:error, {:auth_failed, _}} = connect(fn _ -> [] end, user: "someone-else")
  end

  test "falls back to version 1 when the server refuses version 2" do
    assert {:ok, client} = connect(fn _ -> [batch1()] end, [], versions: [1])
    assert client.protocol_version == 1
    assert client.session_id == "session-1"
    assert {:ok, df} = CubeNativeClient.query_df(client, "SELECT 1")
    assert DF.n_rows(df) == 3
  end

  test "a user is never dropped by falling back to version 1" do
    assert {:error, {:server, "UNSUPPORTED_VERSION", _}} =
             connect(fn _ -> [] end, [user: "cube"], versions: [1])

    assert_raise ArgumentError, fn ->
      connect(fn _ -> [] end, user: "cube", protocol_version: 1)
    end
  end

  test "protocol_version: 1 speaks version 1" do
    assert {:ok, %{protocol_version: 1}} = connect(fn _ -> [] end, protocol_version: 1)
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
