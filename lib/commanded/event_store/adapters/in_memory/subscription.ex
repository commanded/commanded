defmodule Commanded.EventStore.Adapters.InMemory.Subscription do
  @moduledoc false

  use GenServer

  alias Commanded.EventStore.Adapters.InMemory.Subscription

  defstruct [:stream_uuid, :name, :subscriber, :ref, :start_from, last_seen_event_number: 0]

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
  def handle_info({:events, stream_uuid, events}, %Subscription{} = state) do
    %Subscription{subscriber: subscriber, stream_uuid: subscription_stream_uuid} = state

    if subscription_stream_uuid in [:all, stream_uuid] do
      send(subscriber, {:events, events})
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, reason}, %Subscription{} = state) do
    {:stop, reason, state}
  end
end
