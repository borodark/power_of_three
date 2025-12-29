defmodule PowerOfThree.CubeConnection do
  @moduledoc """
  Manages connections to Cube and executes queries via ADBC.

  This module provides functions for connecting to Cube.js via the
  cubesqld Arrow Native protocol and executing SQL queries.

  ## Configuration

  Configure the Cube connection in your application config:

      config :power_of_three, PowerOfThree.CubeConnection,
        host: "localhost",
        port: 8120,
        token: "test",
        username: "username",
        password: "password"

  Or pass options directly:

      {:ok, conn} = CubeConnection.connect(
        host: "localhost",
        port: 8120,
        token: "test"
      )

  ## Usage

      # Execute a query
      {:ok, result} = CubeConnection.query(conn, "SELECT 1 as test")

      # Get results as DataFrame (recommended)
      {:ok, df} = PowerOfThree.CubeFrame.from_query(conn, "SELECT * FROM cube_name LIMIT 10")

  """

  @type connection :: pid()
  @type query_result :: Adbc.Result.t()
  @type query_error :: Adbc.Error.t()

  @type connect_opts :: [
          host: String.t(),
          port: pos_integer(),
          token: String.t(),
          username: String.t() | nil,
          password: String.t() | nil,
          driver_path: String.t() | nil
        ]

  @doc """
  Connects to Cube via ADBC.

  ## Options

    * `:host` - Cube host (default: "localhost")
    * `:port` - Cube port (default: 8120)
    * `:token` - Cube authentication token
    * `:username` - Optional username
    * `:password` - Optional password
    * `:driver_path` - Path to Cube ADBC driver (auto-detected if not provided)

  ## Examples

      {:ok, conn} = CubeConnection.connect(
        host: "localhost",
        port: 8120,
        token: "my-token"
      )
  """
  @spec connect(connect_opts()) :: {:ok, connection()} | {:error, term()}
  def connect(
        opts \\ [
          host: "localhost",
          port: 8120,
          token: "test",
          username: "username",
          password: "password"
        ]
      ) do
    opts = merge_config(opts)

    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, 8120)
    token = Keyword.fetch!(opts, :token)
    username = Keyword.get(opts, :username)
    password = Keyword.get(opts, :password)
    driver_path = Keyword.get(opts, :driver_path) || find_cube_driver()

    with {:ok, db} <- start_database(driver_path, host, port, token),
         {:ok, conn} <- start_connection(db, username, password) do
      {:ok, conn}
    end
  end

  @doc """
  Executes a SQL query on the Cube connection.

  ## Examples

      {:ok, result} = CubeConnection.query(conn, "SELECT 1 as test")
  """
  @spec query(connection(), String.t()) :: {:ok, query_result()} | {:error, query_error()}
  def query(conn, sql) when is_binary(sql) do
    case Adbc.Connection.query(conn, sql) do
      {:ok, result} -> {:ok, Adbc.Result.materialize(result)}
      error -> error
    end
  end

  @doc """
  Executes a SQL query with parameters and options.

  ## Examples

      {:ok, result} = CubeConnection.query(conn, "SELECT * FROM orders WHERE id = ?", [123])
  """
  @spec query(connection(), String.t(), list(), keyword()) ::
          {:ok, query_result()} | {:error, query_error()}
  def query(conn, sql, params, _opts \\ []) when is_binary(sql) and is_list(params) do
    # For now, ADBC doesn't support parameterized queries with Cube
    # So we'll just call the simple query/2 version
    # In the future, this could be extended to support parameters
    query(conn, sql)
  end

  @doc """
  Executes a SQL query and raises on error.

  ## Examples

      result = CubeConnection.query!(conn, "SELECT 1 as test")
  """
  @spec query!(connection(), String.t()) :: query_result()
  def query!(conn, sql) do
    case query(conn, sql) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Disconnects from Cube.

  ## Examples

      :ok = CubeConnection.disconnect(conn)
  """
  @spec disconnect(connection()) :: :ok
  def disconnect(conn) when is_pid(conn) do
    GenServer.stop(conn, :normal)
  end

  # Private functions

  defp merge_config(opts) do
    app_config = Application.get_env(:power_of_three, __MODULE__, [])
    Keyword.merge(app_config, opts)
  end

  defp start_database(driver_path, host, port, token) do
    db_opts = [
      driver: driver_path,
      "adbc.cube.host": host,
      "adbc.cube.port": Integer.to_string(port),
      "adbc.cube.connection_mode": "native",
      "adbc.cube.token": token
    ]

    Adbc.Database.start_link(db_opts)
  end

  # TODO poolboy this
  defp start_connection(db, username, password) do
    conn_opts = [database: db]

    conn_opts =
      if username do
        conn_opts ++ [{"adbc.cube.username", username}]
      else
        conn_opts
      end

    conn_opts =
      if password do
        conn_opts ++ [{"adbc.cube.password", password}]
      else
        conn_opts
      end

    Adbc.Connection.start_link(conn_opts)
  end

  defp find_cube_driver do
    # Look for the Cube driver in common locations
    possible_paths = [
      # Relative to adbc project
      # TODO Noice
      # Path.expand("~/projects/learn_erl/adbc/_build/dev/lib/adbc/priv/adbc_driver_cube.so"),
      # In the application's priv directory
      Path.join(:code.priv_dir(:adbc), "adbc_driver_cube.so")
    ]

    Enum.find(possible_paths, fn path ->
      File.exists?(path)
    end) || raise "Cube ADBC driver not found. Please specify :driver_path option."
  end
end
