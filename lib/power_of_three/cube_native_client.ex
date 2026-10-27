defmodule PowerOfThree.CubeNativeClient do
  @moduledoc """
  Pure-Elixir client for CubeSQL's Arrow Native server (port 8120).

  Speaks the Arrow Native protocol over `:gen_tcp` and decodes the Arrow IPC
  payloads with Explorer. No driver or NIF beyond Explorer's own.

  ## Examples

      {:ok, client} = PowerOfThree.CubeNativeClient.connect(token: "test")
      {:ok, df} = PowerOfThree.CubeNativeClient.query_df(client, "SELECT * FROM of_customers LIMIT 10")

      # Or through the cube macros
      Customer.df(columns: [...], connection_type: :native, connection_opts: [token: "test"])

  A client holds one socket and must not be used by two processes at once.
  """

  alias PowerOfThree.CubeNative.Protocol

  defstruct [:socket, :server_version, :session_id, :timeout]

  @type t :: %__MODULE__{}
  @type result :: %{schema: binary() | nil, batches: [binary()], rows_affected: integer()}

  @doc """
  Connects, performs the handshake and authenticates.

  ## Options

    * `:host` - Cube host (default: "localhost")
    * `:port` - Arrow Native port (default: 8120)
    * `:token` - Cube authentication token (required)
    * `:database` - Optional database name
    * `:timeout` - Connect and receive timeout in ms (default: 30_000)

  Options are merged over `config :power_of_3, PowerOfThree.CubeNativeClient, ...`.
  """
  @spec connect(keyword()) :: {:ok, t()} | {:error, term()}
  def connect(opts \\ []) do
    opts = merge_config(opts)
    host = opts |> Keyword.get(:host, "localhost") |> String.to_charlist()
    port = Keyword.get(opts, :port, 8120)
    token = Keyword.fetch!(opts, :token)
    database = Keyword.get(opts, :database)
    timeout = Keyword.get(opts, :timeout, 30_000)

    sock_opts = [:binary, packet: 4, active: false, nodelay: true]

    with {:ok, socket} <- :gen_tcp.connect(host, port, sock_opts, timeout) do
      client = %__MODULE__{socket: socket, timeout: timeout}

      case handshake(client, token, database) do
        {:ok, client} ->
          {:ok, client}

        error ->
          :gen_tcp.close(socket)
          error
      end
    end
  end

  @doc """
  Runs `sql` and returns the raw Arrow IPC payloads.

  Each entry in `:batches` is a self-contained Arrow IPC stream.
  """
  @spec query(t(), String.t()) :: {:ok, result()} | {:error, term()}
  def query(%__MODULE__{} = client, sql) when is_binary(sql) do
    with :ok <- send_msg(client, {:query_request, sql}) do
      collect(client, %{schema: nil, batches: [], rows_affected: 0})
    end
  end

  @doc """
  Runs `sql` and returns an `Explorer.DataFrame`.
  """
  @spec query_df(t(), String.t()) :: {:ok, Explorer.DataFrame.t()} | {:error, term()}
  def query_df(%__MODULE__{} = client, sql) when is_binary(sql) do
    with {:ok, result} <- query(client, sql), do: to_dataframe(result)
  end

  @doc """
  Decodes a `query/2` result into an `Explorer.DataFrame`.
  """
  @spec to_dataframe(result()) :: {:ok, Explorer.DataFrame.t()} | {:error, term()}
  # A zero-row result still carries the schema: an IPC stream with no batches.
  def to_dataframe(%{batches: [], schema: nil}), do: {:ok, Explorer.DataFrame.new([])}
  def to_dataframe(%{batches: [], schema: schema}), do: Explorer.DataFrame.load_ipc_stream(schema)
  def to_dataframe(%{batches: [ipc]}), do: Explorer.DataFrame.load_ipc_stream(ipc)

  def to_dataframe(%{batches: batches}) do
    batches
    |> Enum.reduce_while([], fn ipc, acc ->
      case Explorer.DataFrame.load_ipc_stream(ipc) do
        {:ok, df} -> {:cont, [df | acc]}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:error, _} = error -> error
      dfs -> {:ok, dfs |> Enum.reverse() |> Explorer.DataFrame.concat_rows()}
    end
  end

  @doc """
  Whether `result` leaves the client unusable.

  A server Error frame ends its response cleanly, so the client can run the
  next query. Anything else that fails mid-exchange (closed socket, timeout,
  undecodable frame) may leave unread frames behind, and the next query would
  read them as its own result: the client must be closed and replaced.
  """
  @spec broken?(term()) :: boolean()
  def broken?({:error, {:server, _code, _message}}), do: false
  def broken?({:error, :params_not_supported_by_native_transport}), do: false
  def broken?({:error, _}), do: true
  def broken?(_), do: false

  @spec close(t()) :: :ok
  def close(%__MODULE__{socket: socket}), do: :gen_tcp.close(socket)

  defp merge_config(opts) do
    app_config =
      Application.get_env(:power_of_3, __MODULE__, []) ++
        Application.get_env(:power_of_three, __MODULE__, [])

    Keyword.merge(app_config, opts)
  end

  defp handshake(client, token, database) do
    with :ok <- send_msg(client, {:handshake_request, Protocol.version()}),
         {:ok, {:handshake_response, version, server_version}} <- recv_msg(client),
         :ok <- check_version(version),
         :ok <- send_msg(client, {:auth_request, token, database}),
         {:ok, {:auth_response, true, session_id}} <- recv_msg(client) do
      {:ok, %{client | server_version: server_version, session_id: session_id}}
    else
      {:ok, {:auth_response, false, reason}} -> {:error, {:auth_failed, reason}}
      {:ok, {:error, code, message}} -> {:error, {:server, code, message}}
      {:ok, other} -> {:error, {:unexpected, other}}
      {:error, _} = error -> error
    end
  end

  # The server may send an Error frame at any point, including after the schema.
  defp collect(client, acc) do
    case recv_msg(client) do
      {:ok, {:schema, ipc}} ->
        collect(client, %{acc | schema: ipc})

      {:ok, {:batch, ipc}} ->
        collect(client, %{acc | batches: [ipc | acc.batches]})

      {:ok, {:complete, rows}} ->
        {:ok, %{acc | batches: Enum.reverse(acc.batches), rows_affected: rows}}

      {:ok, {:error, code, message}} ->
        {:error, {:server, code, message}}

      {:ok, other} ->
        {:error, {:unexpected, other}}

      {:error, _} = error ->
        error
    end
  end

  defp check_version(version) do
    if version == Protocol.version(), do: :ok, else: {:error, {:version_mismatch, version}}
  end

  defp send_msg(%{socket: socket}, msg), do: :gen_tcp.send(socket, Protocol.encode(msg))

  defp recv_msg(%{socket: socket, timeout: timeout}) do
    with {:ok, payload} <- :gen_tcp.recv(socket, 0, timeout), do: Protocol.decode(payload)
  end
end
