defmodule EventStore.Publisher do
  @moduledoc """
  Publish events ordered by event id
  """

  use GenServer

  require Logger

  alias EventStore.{Publisher,Storage,Subscriptions}

  defmodule PendingEvents do
    defstruct [
      initial_event_id: nil,
      last_event_id: nil,
      stream_uuid: nil,
      events: [],
    ]
  end

  defstruct [
    last_published_event_id: 0,
    pending_events: %{},
    serializer: nil,
  ]

  def start_link(serializer) do
    GenServer.start_link(__MODULE__, %Publisher{serializer: serializer}, name: __MODULE__)
  end

  def notify_events(stream_uuid, events) do
    GenServer.cast(__MODULE__, {:notify_events, stream_uuid, events})
  end

  def init(%Publisher{} = state) do
    GenServer.cast(self(), {:fetch_latest_event_id})
    {:ok, state}
  end

  def handle_cast({:fetch_latest_event_id}, %Publisher{} = state) do
    {:ok, latest_event_id} = Storage.latest_event_id()

    {:noreply, %Publisher{state | last_published_event_id: latest_event_id}}
  end

  def handle_cast({:notify_pending_events}, %Publisher{last_published_event_id: last_published_event_id, pending_events: pending_events, serializer: serializer} = state) do
    next_event_id = last_published_event_id + 1

    state = case Map.get(pending_events, next_event_id) do
      %PendingEvents{stream_uuid: stream_uuid, events: events, last_event_id: last_event_id} ->
        Subscriptions.notify_events(stream_uuid, events, serializer)

        %Publisher{state |
          last_published_event_id: last_event_id,
          pending_events: Map.delete(pending_events, next_event_id),
        }

      nil ->
        state
    end

    {:noreply, state}
  end

  def handle_cast({:notify_events, stream_uuid, events}, %Publisher{last_published_event_id: last_published_event_id, pending_events: pending_events, serializer: serializer} = state) do
    expected_event_id = last_published_event_id + 1
    initial_event_id = first_event_id(events)
    last_event_id = last_event_id(events)

    state = case initial_event_id do
      ^expected_event_id ->
        # events are in expected order, immediately notify subscribers
        Subscriptions.notify_events(stream_uuid, events, serializer)

        %Publisher{state |
          last_published_event_id: last_event_id,
        }

      initial_event_id ->
        # events are out of order
        pending = %PendingEvents{
          initial_event_id: initial_event_id,
          last_event_id: last_event_id,
          stream_uuid: stream_uuid,
          events: events
        }

        # attempt to publish pending events
        GenServer.cast(self(), {:notify_pending_events})

        %Publisher{state |
          pending_events: Map.put(pending_events, initial_event_id, pending)
        }
    end

    {:noreply, state}
  end

  defp first_event_id([first | _]), do: first.event_id
  defp last_event_id(events), do: List.last(events).event_id
end
