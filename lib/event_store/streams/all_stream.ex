defmodule EventStore.Streams.AllStream do
  @moduledoc """
  A logical stream containing events appended to all streams
  """

  use GenServer
  require Logger

  alias EventStore.{EventData,RecordedEvent,Storage,Writer}
  alias EventStore.Streams.AllStream
  alias EventStore.Subscriptions

  @all_stream "$all"

  defstruct serializer: nil

  def start_link(serializer) do
    GenServer.start_link(__MODULE__, %AllStream{serializer: serializer}, name: __MODULE__)
  end

  def read_stream_forward(start_version \\ 0, count \\ nil) do
    GenServer.call(__MODULE__, {:read_stream_forward, start_version, count})
  end

  def subscribe_to_stream(subscription_name, subscriber) do
    GenServer.call(__MODULE__, {:subscribe_to_stream, subscription_name, subscriber})
  end

  def init(%AllStream{} = state) do
    {:ok, state}
  end

  def handle_call({:read_stream_forward, start_event_id, count}, _from, %AllStream{serializer: serializer} = state) do
    reply = read_storage_forward(start_event_id, count, serializer)

    {:reply, reply, state}
  end

  def handle_call({:subscribe_to_stream, subscription_name, subscriber}, _from, %AllStream{} = state) do
    reply = Subscriptions.subscribe_to_stream(@all_stream, self, subscription_name, subscriber)

    {:reply, reply, state}
  end

  defp read_storage_forward(start_event_id, count, serializer) do
    {:ok, recorded_events} = Storage.read_all_streams_forward(start_event_id, count)

    events = Enum.map(recorded_events, fn event -> deserialize_recorded_event(event, serializer) end)

    {:ok, events}
  end

  defp deserialize_recorded_event(%RecordedEvent{headers: headers, payload: payload, event_type: event_type} = recorded_event, serializer) do
    %RecordedEvent{recorded_event |
      headers: serializer.deserialize(headers, []),
      payload: serializer.deserialize(payload, type: event_type),
    }
  end
end
