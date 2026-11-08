defmodule PowerOfThree.CubeNativeFakeServer do
  @moduledoc false
  # Stand-in for CubeSQL's Arrow Native server. Accepts any number of
  # connections; `respond` maps SQL to one of:
  #
  #   [df, ...]                 - one batch per DataFrame
  #   {:error, code, message}   - an Error frame
  #   :close                    - drop the connection without answering
  #   {:delay, ms, [df, ...]}   - answer after `ms` milliseconds
  #   {:empty, df}              - a zero-row result: df's schema, no batches
  #
  # The token "test" is accepted; anything else fails auth. A user, sent in
  # protocol version 2, must be "cube" when given. Options:
  #
  #   versions: [1, 2]          - protocol versions the server accepts

  alias PowerOfThree.CubeNative.Protocol
  alias Explorer.DataFrame, as: DF

  def start(respond, opts \\ []) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: 4, active: false])
    serve_on(listen, respond, opts)
  end

  @doc "Serves on an already-open listen socket; returns its port."
  def serve_on(listen, respond, opts \\ []) do
    {:ok, port} = :inet.port(listen)
    versions = Keyword.get(opts, :versions, [1, 2])
    pid = spawn_link(fn -> accept_loop(listen, respond, versions) end)
    :ok = :gen_tcp.controlling_process(listen, pid)
    port
  end

  defp accept_loop(listen, respond, versions) do
    case :gen_tcp.accept(listen) do
      {:ok, sock} ->
        pid = spawn(fn -> serve(sock, respond, versions) end)
        :ok = :gen_tcp.controlling_process(sock, pid)
        accept_loop(listen, respond, versions)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve(sock, respond, versions) do
    {:ok, {:handshake_request, version}} = recv(sock)

    if version in versions do
      send_msg(sock, {:handshake_response, version, "fake"})
      authenticate(sock, respond, version)
    else
      send_msg(sock, {:error, "UNSUPPORTED_VERSION", "Unsupported protocol version #{version}"})
    end
  end

  defp authenticate(sock, respond, version) do
    case recv(sock, version) do
      {:ok, {:auth_request, ^version, user, "test", _}} when user in [nil, "cube"] ->
        send_msg(sock, {:auth_response, true, "session-#{version}"})
        loop(sock, respond)

      {:ok, {:auth_request, ^version, _, _, _}} ->
        send_msg(sock, {:auth_response, false, "bad token"})
    end
  end

  defp loop(sock, respond) do
    case recv(sock) do
      {:ok, {:query_request, sql}} ->
        case answer(sock, respond.(sql)) do
          :closed -> :ok
          :ok -> loop(sock, respond)
        end

      {:error, _} ->
        :ok
    end
  end

  defp answer(sock, :close) do
    :gen_tcp.close(sock)
    :closed
  end

  defp answer(sock, {:delay, ms, dfs}) do
    Process.sleep(ms)
    answer(sock, dfs)
  end

  defp answer(sock, {:empty, df}) do
    send_msg(sock, {:schema, DF.dump_ipc_stream!(DF.head(df, 0))})
    send_msg(sock, {:complete, 0})
  end

  defp answer(sock, {:error, code, message}), do: send_msg(sock, {:error, code, message})

  defp answer(sock, [first | _] = dfs) do
    send_msg(sock, {:schema, DF.dump_ipc_stream!(DF.head(first, 0))})
    Enum.each(dfs, &send_msg(sock, {:batch, DF.dump_ipc_stream!(&1)}))
    send_msg(sock, {:complete, dfs |> Enum.map(&DF.n_rows/1) |> Enum.sum()})
  end

  defp recv(sock, version \\ nil) do
    with {:ok, payload} <- :gen_tcp.recv(sock, 0), do: Protocol.decode(payload, version)
  end

  # The client may already have gone away (e.g. after a timeout).
  defp send_msg(sock, msg) do
    case :gen_tcp.send(sock, Protocol.encode(msg)) do
      :ok -> :ok
      {:error, _} -> :ok
    end
  end
end
