defmodule PowerOfThree.CubeConnectionWorker do
  @moduledoc false

  use GenServer

  alias PowerOfThree.CubeNativeClient

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def connection(worker) do
    GenServer.call(worker, :get_connection)
  end

  @impl true
  def init(opts) do
    case CubeNativeClient.connect(opts) do
      {:ok, client} -> {:ok, client}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_connection, _from, client) do
    {:reply, client, client}
  end

  @impl true
  def terminate(_reason, %CubeNativeClient{} = client) do
    CubeNativeClient.close(client)
  end

  def terminate(_reason, _state), do: :ok
end
