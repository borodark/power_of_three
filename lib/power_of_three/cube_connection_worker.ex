defmodule PowerOfThree.CubeConnectionWorker do
  @moduledoc false

  use GenServer

  alias PowerOfThree.CubeConnection

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def connection(worker) do
    GenServer.call(worker, :get_connection)
  end

  @impl true
  def init(opts) do
    case CubeConnection.connect(opts) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_connection, _from, conn) do
    {:reply, conn, conn}
  end

  @impl true
  def terminate(_reason, conn) when is_pid(conn) do
    try do
      CubeConnection.disconnect(conn)
    catch
      _, _ -> :ok
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok
end
