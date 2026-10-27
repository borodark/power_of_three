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
  alias PowerOfThree.{CubeConnectionWorker, CubeFrame}

  @pool_name :cube_connection_pool

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

  ## Examples

      {:ok, df} = CubeConnectionPool.query("SELECT * FROM orders_no_preagg LIMIT 10")
  """
  def query(sql, params \\ [], opts \\ []) do
    transaction(
      fn client ->
        CubeFrame.from_query(client, sql, params, opts)
      end,
      opts
    )
  end

  @doc """
  Executes a function with a connection from the pool.

  The connection is automatically returned to the pool after the function completes.

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
        conn = CubeConnectionWorker.connection(worker)
        fun.(conn)
      end,
      opts[:timeout] || 60_000
    )
  end

  @doc """
  Checks out a connection from the pool.

  Returns `{worker, client}`; pass the worker back to `checkin/1` when done.

  ## Examples

      {worker, client} = CubeConnectionPool.checkout()
      try do
        CubeNativeClient.query_df(client, "SELECT ...")
      after
        CubeConnectionPool.checkin(worker)
      end
  """
  def checkout(opts \\ []) do
    worker = :poolboy.checkout(@pool_name, opts[:block] || true, opts[:timeout] || 5_000)
    {worker, CubeConnectionWorker.connection(worker)}
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
