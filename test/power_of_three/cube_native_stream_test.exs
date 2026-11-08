defmodule PowerOfThree.CubeNativeStreamTest do
  use ExUnit.Case, async: true

  alias PowerOfThree.CubeNativeClient
  alias PowerOfThree.CubeNativeClient.StreamError
  alias PowerOfThree.CubeNativeFakeServer, as: FakeServer
  alias Explorer.DataFrame, as: DF

  defp batch1, do: DF.new(brand: ["a", "b", "c"], count: [1, 2, 3])
  defp batch2, do: DF.new(brand: ["d", "e"], count: [4, 5])

  defp connect(respond) do
    port = FakeServer.start(respond)
    {:ok, client} = CubeNativeClient.connect(port: port, token: "test")
    client
  end

  defp counts(payloads) do
    Enum.flat_map(
      payloads,
      &(&1 |> DF.load_ipc_stream!() |> DF.to_columns(atom_keys: true)).count
    )
  end

  test "yields each batch's IPC payload in order" do
    client = connect(fn _ -> [batch1(), batch2()] end)
    payloads = client |> CubeNativeClient.stream("SELECT brand, count FROM x") |> Enum.to_list()

    assert length(payloads) == 2
    assert counts(payloads) == [1, 2, 3, 4, 5]
  end

  test "sends nothing until the stream runs, and the client works after" do
    test = self()

    client =
      connect(fn sql ->
        send(test, {:query, sql})
        [batch1()]
      end)

    stream = CubeNativeClient.stream(client, "SELECT 1")
    refute_receive {:query, _}, 50

    assert counts(Enum.to_list(stream)) == [1, 2, 3]
    assert_received {:query, "SELECT 1"}
    assert {:ok, df} = CubeNativeClient.query_df(client, "SELECT 2")
    assert DF.n_rows(df) == 3
  end

  test "a zero-row result yields its schema" do
    client = connect(fn _ -> {:empty, batch1()} end)

    assert [schema] = client |> CubeNativeClient.stream("SELECT nothing") |> Enum.to_list()
    df = DF.load_ipc_stream!(schema)
    assert DF.names(df) == ["brand", "count"]
    assert DF.n_rows(df) == 0
  end

  test "a server error raises, and leaves the client usable" do
    client =
      connect(fn
        "SELECT nope" -> {:error, "QUERY_ERROR", "no such cube"}
        _ -> [batch1()]
      end)

    error =
      assert_raise StreamError, fn ->
        client |> CubeNativeClient.stream("SELECT nope") |> Enum.to_list()
      end

    assert error.reason == {:server, "QUERY_ERROR", "no such cube"}
    assert {:ok, _} = CubeNativeClient.query(client, "SELECT 1")
  end

  test "stopping early closes the client, whose next query reports it broken" do
    client = connect(fn _ -> [batch1(), batch2()] end)

    assert [_first] = client |> CubeNativeClient.stream("SELECT brand FROM x") |> Enum.take(1)

    result = CubeNativeClient.query(client, "SELECT 1")
    assert CubeNativeClient.broken?(result)
  end

  test "a dropped connection raises" do
    client = connect(fn _ -> :close end)

    assert_raise StreamError, fn ->
      client |> CubeNativeClient.stream("SELECT 1") |> Enum.to_list()
    end
  end

  describe "with ex_arrow" do
    test "decodes each payload into record batches as it arrives" do
      client = connect(fn _ -> [batch1(), batch2()] end)

      batches =
        client
        |> CubeNativeClient.stream_record_batches("SELECT brand, count FROM x")
        |> Enum.to_list()

      assert Enum.map(batches, &ExArrow.RecordBatch.num_rows/1) == [3, 2]
      assert ExArrow.RecordBatch.column_names(hd(batches)) == ["brand", "count"]
    end

    test "a zero-row result yields no batches" do
      client = connect(fn _ -> {:empty, batch1()} end)

      assert [] ==
               client
               |> CubeNativeClient.stream_record_batches("SELECT nothing")
               |> Enum.to_list()
    end
  end
end
