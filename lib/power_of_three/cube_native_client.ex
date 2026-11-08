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

  defstruct [:socket, :server_version, :session_id, :timeout, :protocol_version]

  @type t :: %__MODULE__{}
  @type result :: %{schema: binary() | nil, batches: [binary()], rows_affected: integer()}

  @doc """
  Connects, performs the handshake and authenticates.

  ## Options

    * `:host` - Cube host (default: "localhost")
    * `:port` - Arrow Native port (default: 8120)
    * `:token` - Cube authentication token (required), the SQL API password
    * `:user` - Optional SQL API user name; authenticates as the Postgres
      endpoint does for the same user and password (protocol version 2)
    * `:database` - Optional database name
    * `:protocol_version` - 2 (default) or 1. A server that only speaks
      version 1 refuses version 2; the client then reconnects with version 1,
      unless `:user` is set, which version 1 cannot carry
    * `:timeout` - Connect and receive timeout in ms (default: 30_000)

  Options are merged over `config :power_of_3, PowerOfThree.CubeNativeClient, ...`.
  """
  @spec connect(keyword()) :: {:ok, t()} | {:error, term()}
  def connect(opts \\ []) do
    opts = merge_config(opts)
    host = opts |> Keyword.get(:host, "localhost") |> String.to_charlist()
    port = Keyword.get(opts, :port, 8120)

    auth = %{
      token: Keyword.fetch!(opts, :token),
      user: Keyword.get(opts, :user),
      database: Keyword.get(opts, :database)
    }

    timeout = Keyword.get(opts, :timeout, 30_000)
    version = Keyword.get(opts, :protocol_version, Protocol.version())

    unless Protocol.supported_version?(version),
      do: raise(ArgumentError, "unsupported :protocol_version #{inspect(version)}")

    if version == 1 and auth.user,
      do: raise(ArgumentError, ":user needs :protocol_version 2")

    case connect(host, port, timeout, version, auth) do
      # A server older than version 2 refuses it in the handshake
      {:error, {:server, "UNSUPPORTED_VERSION", _}} when version > 1 and is_nil(auth.user) ->
        connect(host, port, timeout, 1, auth)

      result ->
        result
    end
  end

  defp connect(host, port, timeout, version, auth) do
    sock_opts = [:binary, packet: 4, active: false, nodelay: true]

    with {:ok, socket} <- :gen_tcp.connect(host, port, sock_opts, timeout) do
      client = %__MODULE__{socket: socket, timeout: timeout, protocol_version: version}

      case handshake(client, auth) do
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
  Runs `sql` and returns a lazy stream of its Arrow IPC payloads, each a
  self-contained Arrow IPC stream, as the server sends them.

  Nothing is sent until the stream is run. Rows are read from the socket only
  as the stream is consumed, so a large result is never held whole: TCP holds
  the server back while the reader is busy.

  A zero-row result yields its schema as one payload with no batches, so a
  reader always sees the columns. A server error raises
  `PowerOfThree.CubeNativeClient.StreamError`.

  A stream stopped before its last payload (`Enum.take/2`, an exception) leaves
  frames unread, which the next query would read as its own: the client's
  socket is closed then, and the client must be replaced (`broken?/1` is true
  for whatever it returns next).
  """
  @spec stream(t(), String.t()) :: Enumerable.t()
  def stream(%__MODULE__{} = client, sql) when is_binary(sql) do
    Stream.resource(
      fn ->
        case send_msg(client, {:query_request, sql}) do
          :ok -> %{schema: nil, batches?: false}
          {:error, reason} -> raise_stream_error(client, reason)
        end
      end,
      fn
        state when not is_map(state) ->
          {:halt, state}

        state ->
          case recv_msg(client) do
            {:ok, {:schema, ipc}} ->
              {[], %{state | schema: ipc}}

            {:ok, {:batch, ipc}} ->
              {[ipc], %{state | batches?: true}}

            {:ok, {:complete, _rows}} ->
              if state.batches? or is_nil(state.schema),
                do: {[], :done},
                else: {[state.schema], :done}

            # A server error ends its response cleanly
            {:ok, {:error, code, message}} ->
              {:halt, {:failed, {:server, code, message}}}

            {:ok, other} ->
              {:halt, {:broken, {:unexpected, other}}}

            {:error, reason} ->
              {:halt, {:broken, reason}}
          end
      end,
      fn
        :done ->
          :ok

        {:failed, reason} ->
          raise __MODULE__.StreamError, reason: reason

        {:broken, reason} ->
          raise_stream_error(client, reason)

        # Stopped by the reader before the last payload
        _unfinished ->
          close(client)
      end
    )
  end

  @doc """
  Runs `sql` and returns a lazy stream of `ExArrow.RecordBatch`es, decoded
  with ex_arrow one payload at a time as they arrive. See `stream/2`.

  Batches with no rows are left out, so a zero-row result yields none. Needs
  the optional `:ex_arrow` dependency.
  """
  @spec stream_record_batches(t(), String.t()) :: Enumerable.t()
  def stream_record_batches(%__MODULE__{} = client, sql) when is_binary(sql) do
    unless Code.ensure_loaded?(ExArrow.IPC.Reader),
      do: raise(ArgumentError, "stream_record_batches/2 needs the :ex_arrow dependency")

    client
    |> stream(sql)
    |> Stream.flat_map(&record_batches!/1)
    |> Stream.reject(&(ExArrow.RecordBatch.num_rows(&1) == 0))
  end

  @doc """
  Decodes one IPC payload of `stream/2` into its `ExArrow.RecordBatch`es.
  Needs the optional `:ex_arrow` dependency.
  """
  @spec record_batches!(binary()) :: [struct()]
  def record_batches!(ipc) when is_binary(ipc) do
    case ExArrow.IPC.Reader.from_binary(ipc) do
      {:ok, ipc_stream} -> read_record_batches(ipc_stream, [])
      {:error, reason} -> raise __MODULE__.StreamError, reason: {:decode, reason}
    end
  end

  defp read_record_batches(ipc_stream, acc) do
    case ExArrow.Stream.next(ipc_stream) do
      nil -> Enum.reverse(acc)
      {:error, reason} -> raise __MODULE__.StreamError, reason: {:decode, reason}
      batch -> read_record_batches(ipc_stream, [batch | acc])
    end
  end

  # Leaves the socket in an unknown state, so it is closed.
  defp raise_stream_error(client, reason) do
    close(client)
    raise __MODULE__.StreamError, reason: reason
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

  defp handshake(%{protocol_version: version} = client, auth) do
    with :ok <- send_msg(client, {:handshake_request, version}),
         {:ok, {:handshake_response, ^version, server_version}} <- recv_msg(client),
         :ok <- send_msg(client, {:auth_request, version, auth.user, auth.token, auth.database}),
         {:ok, {:auth_response, true, session_id}} <- recv_msg(client) do
      {:ok, %{client | server_version: server_version, session_id: session_id}}
    else
      {:ok, {:handshake_response, other, _}} -> {:error, {:version_mismatch, other}}
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

  defp send_msg(%{socket: socket}, msg), do: :gen_tcp.send(socket, Protocol.encode(msg))

  defp recv_msg(%{socket: socket, timeout: timeout}) do
    with {:ok, payload} <- :gen_tcp.recv(socket, 0, timeout), do: Protocol.decode(payload)
  end
end

defmodule PowerOfThree.CubeNativeClient.StreamError do
  @moduledoc """
  Raised by `PowerOfThree.CubeNativeClient.stream/2` when a streamed query
  fails. `:reason` is what `query/2` would return as `{:error, reason}`, or
  `{:decode, message}` for a payload ex_arrow could not read.
  """
  defexception [:reason]

  @impl true
  def message(%{reason: reason}), do: "native stream failed: #{inspect(reason)}"
end
