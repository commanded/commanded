defmodule Commanded.EventStore.Adapters.InMemory.Subscription do
  @moduledoc false

  use GenServer

  alias Commanded.EventStore.Adapters.InMemory.Subscription

  defstruct [:stream_uuid, :name, :subscriber, :ref, :start_from, last_seen: 0]

  def start_link(%Subscription{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl GenServer
  def init(%Subscription{} = state) do
    %Subscription{subscriber: subscriber} = state

    send(subscriber, {:subscribed, self()})

    state = %Subscription{state | ref: Process.monitor(subscriber)}

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:events, events}, %Subscription{} = state) do
    %Subscription{subscriber: subscriber} = state

    send(subscriber, {:events, events})

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %Subscription{} = state) do
    {:stop, reason, state}
  end
end
