defmodule PowerOfThree.CubeConnectionPoolTest do
  # The pool registers a global name, so these tests can't run concurrently.
  use ExUnit.Case, async: false

  alias PowerOfThree.CubeConnectionPool
  alias PowerOfThree.CubeNativeFakeServer, as: FakeServer
  alias Explorer.DataFrame, as: DF

  defp start_pool(respond, opts \\ []) do
    port = FakeServer.start(respond)

    start_supervised!(
      {CubeConnectionPool,
       Keyword.merge([size: 1, max_overflow: 0, port: port, token: "test"], opts)}
    )
  end

  defp df(n), do: DF.new(n: [n])

  test "queries return DataFrames" do
    start_pool(fn _ -> [df(1)] end)
    assert {:ok, result} = CubeConnectionPool.query("SELECT 1")
    assert DF.to_columns(result, atom_keys: true).n == [1]
  end

  test "a server error leaves the connection usable" do
    start_pool(fn
      "bad" -> {:error, "QUERY_ERROR", "no such cube"}
      _ -> [df(2)]
    end)

    assert {:error, {:server, "QUERY_ERROR", _}} = CubeConnectionPool.query("bad")
    assert {:ok, result} = CubeConnectionPool.query("good")
    assert DF.to_columns(result, atom_keys: true).n == [2]
  end

  test "a dropped connection is replaced and the query retried once" do
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    start_pool(fn _ ->
      # The first attempt kills the connection; later ones succeed.
      case Agent.get_and_update(calls, &{&1, &1 + 1}) do
        0 -> :close
        _ -> [df(3)]
      end
    end)

    assert {:ok, result} = CubeConnectionPool.query("first")
    assert DF.to_columns(result, atom_keys: true).n == [3]
    assert Agent.get(calls, & &1) == 2

    assert {:ok, _} = CubeConnectionPool.query("second")
  end

  test "a connection that keeps dying is reported, not retried forever" do
    start_pool(fn _ -> :close end)
    assert {:error, :closed} = CubeConnectionPool.query("doomed")
  end

  test "a timed-out query doesn't leak its late answer into the next query" do
    start_pool(
      fn
        "slow" -> {:delay, 300, [df("slow")]}
        "fast" -> [df("fast")]
      end,
      timeout: 100
    )

    assert {:error, :timeout} = CubeConnectionPool.query("slow")
    # Let the slow answer arrive on the old socket.
    Process.sleep(400)
    assert {:ok, result} = CubeConnectionPool.query("fast")
    assert DF.to_columns(result, atom_keys: true).n == ["fast"]
  end
end
