defmodule PowerOfThree.CubeConnectionPool do
  @moduledoc """
  Connection pool for Cube ADBC connections using poolboy.

  This module manages a pool of ADBC connections to Cube, enabling
  efficient connection reuse for query execution.

  ## Configuration

  Configure the pool in your application config:

      config :power_of_three, PowerOfThree.CubeConnectionPool,
        size: 10,
        max_overflow: 5,
        host: "localhost",
        port: 8120,
        token: "test",
        username: nil,
        password: nil

  ## Usage

      # Execute a query using a pooled connection
      PowerOfThree.CubeConnectionPool.query("SELECT * FROM orders_no_preagg LIMIT 10")

      # Or check out a connection for multiple operations
      PowerOfThree.CubeConnectionPool.transaction(fn conn ->
        {:ok, result1} = PowerOfThree.CubeConnection.query(conn, "SELECT ...")
        {:ok, result2} = PowerOfThree.CubeConnection.query(conn, "SELECT ...")
        {result1, result2}
      end)
  """

  use GenServer
  alias PowerOfThree.CubeConnection

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
    * `:username` - Optional username
    * `:password` - Optional password
  """
  def start_link(opts \\ []) do
    pool_config = build_pool_config(opts)
    :poolboy.start_link(pool_config, opts)
  end

  @doc """
  Executes a query using a connection from the pool.

  ## Examples

      {:ok, result} = CubeConnectionPool.query("SELECT * FROM orders_no_preagg LIMIT 10")
  """
  def query(sql, params \\ [], opts \\ []) do
    :poolboy.transaction(
      @pool_name,
      fn conn ->
        CubeConnection.query(conn, sql, params, opts)
      end,
      opts[:timeout] || 60_000
    )
  end

  @doc """
  Executes a function with a connection from the pool.

  The connection is automatically returned to the pool after the function completes.

  ## Examples

      result = CubeConnectionPool.transaction(fn conn ->
        {:ok, r1} = CubeConnection.query(conn, "SELECT ...")
        {:ok, r2} = CubeConnection.query(conn, "SELECT ...")
        {r1, r2}
      end)
  """
  def transaction(fun, opts \\ []) do
    :poolboy.transaction(
      @pool_name,
      fun,
      opts[:timeout] || 60_000
    )
  end

  @doc """
  Checks out a connection from the pool.

  Remember to check it back in with `checkin/1` when done.

  ## Examples

      conn = CubeConnectionPool.checkout()
      try do
        CubeConnection.query(conn, "SELECT ...")
      after
        CubeConnectionPool.checkin(conn)
      end
  """
  def checkout(opts \\ []) do
    :poolboy.checkout(@pool_name, opts[:block] || true, opts[:timeout] || 5_000)
  end

  @doc """
  Checks a connection back into the pool.
  """
  def checkin(conn) do
    :poolboy.checkin(@pool_name, conn)
  end

  @doc """
  Returns the pool status.
  """
  def status do
    :poolboy.status(@pool_name)
  end

  ## Server Callbacks (Worker Implementation)

  @impl true
  def init(opts) do
    # Each worker maintains a single ADBC connection
    case CubeConnection.connect(opts) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:query, sql, params, opts}, _from, conn) do
    result = CubeConnection.query(conn, sql, params, opts)
    {:reply, result, conn}
  end

  @impl true
  def handle_call(:get_connection, _from, conn) do
    {:reply, conn, conn}
  end

  @impl true
  def terminate(_reason, conn) when is_pid(conn) do
    # Clean up the connection when the worker terminates
    try do
      CubeConnection.disconnect(conn)
    catch
      _, _ -> :ok
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Private Functions

  defp build_pool_config(opts) do
    config = Application.get_env(:power_of_three, __MODULE__, [])
    opts = Keyword.merge(config, opts)

    [
      name: {:local, @pool_name},
      worker_module: __MODULE__,
      size: opts[:size] || 5,
      max_overflow: opts[:max_overflow] || 2,
      strategy: :fifo
    ]
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
