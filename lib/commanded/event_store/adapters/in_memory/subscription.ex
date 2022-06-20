defmodule Commanded.EventStore.Adapters.InMemory.Subscription do
  @moduledoc false

  use GenServer

  def start_link(subscriber) do
    GenServer.start_link(__MODULE__, subscriber)
  end

  @impl GenServer
  def init(subscriber) do
    send(subscriber, {:subscribed, self()})

    Process.monitor(subscriber)

    {:ok, subscriber}
  end

  @impl GenServer
  def handle_info({:events, events}, subscriber) do
    send(subscriber, {:events, events})

    {:noreply, subscriber}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, subscriber, reason}, subscriber) do
    {:stop, reason, subscriber}
  end
end
