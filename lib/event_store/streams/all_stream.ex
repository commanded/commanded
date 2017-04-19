defmodule EventStore.Streams.AllStream do
  @moduledoc """
  A logical stream containing events appended to all streams
  """

  use GenServer
  require Logger

  alias EventStore.{RecordedEvent,Storage}
  alias EventStore.Streams.AllStream
  alias EventStore.Subscriptions

  defstruct serializer: nil

  def start_link(serializer) do
    GenServer.start_link(__MODULE__, %AllStream{serializer: serializer}, name: __MODULE__)
  end

  def read_stream_forward(start_event_id, count) do
    GenServer.call(__MODULE__, {:read_stream_forward, start_event_id, count})
  end

  def stream_forward(start_event_id, read_batch_size) do
    GenServer.call(__MODULE__, {:stream_forward, start_event_id, read_batch_size})
  end

  def subscribe_to_stream(subscription_name, subscriber, opts) do
    GenServer.call(__MODULE__, {:subscribe_to_stream, subscription_name, subscriber, opts})
  end

  def init(%AllStream{} = state) do
    {:ok, state}
  end

  def handle_call({:read_stream_forward, start_event_id, count}, _from, %AllStream{serializer: serializer} = state) do
    reply = read_storage_forward(start_event_id, count, serializer)

    {:reply, reply, state}
  end

  def handle_call({:stream_forward, start_event_id, read_batch_size}, _from, %AllStream{serializer: serializer} = state) do
    reply = stream_storage_forward(start_event_id, read_batch_size, serializer)

    {:reply, reply, state}
  end

  def handle_call({:subscribe_to_stream, subscription_name, subscriber, opts}, _from, %AllStream{} = state) do
    {start_from, opts} = Keyword.pop(opts, :start_from, :origin)

    opts = Keyword.merge([start_from_event_id: start_from_event_id(start_from)], opts)

    reply = Subscriptions.subscribe_to_all_streams(self(), subscription_name, subscriber, opts)

    {:reply, reply, state}
  end

  defp start_from_event_id(:origin), do: 0
  defp start_from_event_id(:current) do
    {:ok, event_id} = Storage.latest_event_id()
    event_id
  end
  defp start_from_event_id(start_from) when is_integer(start_from), do: start_from

  defp read_storage_forward(start_event_id, count, serializer) do
    case Storage.read_all_streams_forward(start_event_id, count) do
      {:ok, recorded_events} -> {:ok, Enum.map(recorded_events, fn event -> deserialize_recorded_event(event, serializer) end)}
      {:error, _reason} = reply -> reply
    end
  end

  defp stream_storage_forward(0, read_batch_size, serializer), do: stream_storage_forward(1, read_batch_size, serializer)
  defp stream_storage_forward(start_event_id, read_batch_size, serializer) do
    Stream.resource(
      fn -> start_event_id end,
      fn next_event_id ->
        case read_storage_forward(next_event_id, read_batch_size, serializer) do
          {:ok, []} -> {:halt, next_event_id}
          {:ok, events} -> {events, next_event_id + length(events)}
          {:error, _reason} -> {:halt, next_event_id}
        end
      end,
      fn _ -> :ok end
    )
  end

  defp deserialize_recorded_event(%RecordedEvent{data: data, metadata: metadata, event_type: event_type} = recorded_event, serializer) do
    %RecordedEvent{recorded_event |
      data: serializer.deserialize(data, type: event_type),
      metadata: serializer.deserialize(metadata, [])
    }
  end
end
