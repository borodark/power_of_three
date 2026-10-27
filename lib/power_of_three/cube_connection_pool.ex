defmodule PowerOfThree.CubeConnectionPool do
  @moduledoc """
  Connection pool for Cube Arrow Native connections using poolboy.

  Each worker holds one authenticated `PowerOfThree.CubeNativeClient`, so
  queries skip the TCP connect, handshake and auth.

  ## Configuration

  Configure the pool in your application config:

      config :power_of_3, PowerOfThree.CubeConnectionPool,
        size: 10,
        max_overflow: 5,
        host: "localhost",
        port: 8120,
        token: "test",
        database: nil

  ## Usage

      # Execute a query using a pooled connection
      {:ok, df} = PowerOfThree.CubeConnectionPool.query("SELECT * FROM orders_no_preagg LIMIT 10")

      # Or check out a connection for multiple operations
      PowerOfThree.CubeConnectionPool.transaction(fn client ->
        {:ok, df1} = PowerOfThree.CubeNativeClient.query_df(client, "SELECT ...")
        {:ok, df2} = PowerOfThree.CubeNativeClient.query_df(client, "SELECT ...")
        {df1, df2}
      end)
  """

  use Supervisor
  alias PowerOfThree.{CubeConnectionWorker, CubeFrame, CubeNativeClient}

  @pool_name :cube_connection_pool

  # The connection was already dead before the query could run.
  @stale_connection_errors [:closed, :enotconn, :econnreset, :epipe]

  ## Client API

  @doc """
  Starts the connection pool.

  ## Options

    * `:size` - Pool size (default: 5)
    * `:max_overflow` - Maximum number of additional connections (default: 2)
    * `:host` - Cube host (default: "localhost")
    * `:port` - Cube port (default: 8120)
    * `:token` - Cube authentication token (required)
    * `:database` - Optional database name
    * `:timeout` - Connect and receive timeout in ms (default: 30_000)
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a query using a connection from the pool and returns a DataFrame.

  If the pooled connection turns out to be dead (e.g. cubesqld restarted
  while it sat idle), the query is retried once on a fresh connection. Cube
  queries are reads, so the retry is safe.

  ## Examples

      {:ok, df} = CubeConnectionPool.query("SELECT * FROM orders_no_preagg LIMIT 10")
  """
  def query(sql, params \\ [], opts \\ []) do
    run = fn -> transaction(&CubeFrame.from_query(&1, sql, params, opts), opts) end

    case run.() do
      {:error, reason} when reason in @stale_connection_errors -> run.()
      result -> result
    end
  end

  @doc """
  Executes a function with a connection from the pool.

  The connection is automatically returned to the pool after the function completes.
  If `fun` raises, or returns an error that leaves the connection unusable (see
  `PowerOfThree.CubeNativeClient.broken?/1`), the connection is replaced.

  ## Examples

      result = CubeConnectionPool.transaction(fn client ->
        {:ok, df1} = CubeNativeClient.query_df(client, "SELECT ...")
        {:ok, df2} = CubeNativeClient.query_df(client, "SELECT ...")
        {df1, df2}
      end)
  """
  def transaction(fun, opts \\ []) do
    :poolboy.transaction(
      @pool_name,
      fn worker ->
        with {:ok, client} <- CubeConnectionWorker.connection(worker) do
          run_and_check(worker, client, fun)
        end
      end,
      opts[:timeout] || 60_000
    )
  end

  @doc """
  Checks out a connection from the pool.

  Returns `{worker, client}`, or `{:error, reason}` if no connection can be
  made. Pass the worker back to `checkin/1` when done. Prefer `transaction/2`:
  it replaces a connection left broken by a failed query, which a manual
  checkout can't detect.

  ## Examples

      {worker, client} = CubeConnectionPool.checkout()
      try do
        CubeNativeClient.query_df(client, "SELECT ...")
      after
        CubeConnectionPool.checkin(worker)
      end
  """
  def checkout(opts \\ []) do
    worker =
      :poolboy.checkout(@pool_name, Keyword.get(opts, :block, true), opts[:timeout] || 5_000)

    case CubeConnectionWorker.connection(worker) do
      {:ok, client} ->
        {worker, client}

      {:error, _} = error ->
        :poolboy.checkin(@pool_name, worker)
        error
    end
  end

  @doc """
  Checks a connection back into the pool.
  """
  def checkin({worker, _conn}) do
    :poolboy.checkin(@pool_name, worker)
  end

  def checkin(worker) do
    :poolboy.checkin(@pool_name, worker)
  end

  @doc """
  Returns the pool status.
  """
  def status do
    :poolboy.status(@pool_name)
  end

  defp run_and_check(worker, client, fun) do
    result = fun.(client)
    if CubeNativeClient.broken?(result), do: CubeConnectionWorker.discard(worker)
    result
  rescue
    error ->
      CubeConnectionWorker.discard(worker)
      reraise error, __STACKTRACE__
  end

  ## Supervisor Callbacks

  @impl true
  def init(opts) do
    config =
      Application.get_env(:power_of_3, __MODULE__, []) ++
        Application.get_env(:power_of_three, __MODULE__, [])

    opts = Keyword.merge(config, opts)

    pool_config = [
      name: {:local, @pool_name},
      worker_module: CubeConnectionWorker,
      size: opts[:size] || 5,
      max_overflow: opts[:max_overflow] || 2,
      strategy: :fifo
    ]

    worker_opts =
      Keyword.take(opts, [
        :host,
        :port,
        :token,
        :database,
        :timeout
      ])

    children = [
      :poolboy.child_spec(@pool_name, pool_config, worker_opts)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Child spec for use in supervision trees.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
end
