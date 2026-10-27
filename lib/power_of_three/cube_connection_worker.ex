defmodule PowerOfThree.CubeConnectionWorker do
  @moduledoc false
  # Holds one CubeNativeClient. After a failed reconnect the worker keeps
  # running without a client and connects again on the next checkout, so a
  # Cube restart doesn't take the pool down.

  use GenServer

  alias PowerOfThree.CubeNativeClient

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Returns `{:ok, client}`, connecting first if the worker has none."
  def connection(worker) do
    GenServer.call(worker, :get_connection)
  end

  @doc "Closes the current client and drops it; the next checkout reconnects."
  def discard(worker) do
    GenServer.call(worker, :discard)
  end

  @impl true
  def init(opts) do
    case CubeNativeClient.connect(opts) do
      {:ok, client} -> {:ok, %{opts: opts, client: client}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_connection, _from, %{client: nil} = state) do
    case CubeNativeClient.connect(state.opts) do
      {:ok, client} -> {:reply, {:ok, client}, %{state | client: client}}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:get_connection, _from, state) do
    {:reply, {:ok, state.client}, state}
  end

  def handle_call(:discard, _from, state) do
    close(state.client)
    {:reply, :ok, %{state | client: nil}}
  end

  @impl true
  def terminate(_reason, state), do: close(state.client)

  defp close(nil), do: :ok
  defp close(client), do: CubeNativeClient.close(client)
end
