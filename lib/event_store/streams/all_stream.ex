defmodule EventStore.Streams.AllStream do
  @moduledoc """
  A logical stream containing events appended to all streams
  """

  require Logger

  alias EventStore.{RecordedEvent,Storage}
  alias EventStore.Subscriptions

  def read_stream_forward(start_event_id, count) do
    serializer = EventStore.configured_serializer()

    read_storage_forward(start_event_id, count, serializer)
  end

  def stream_forward(start_event_id, read_batch_size) do
    serializer = EventStore.configured_serializer()

    stream_storage_forward(start_event_id, read_batch_size, serializer)
  end

  def subscribe_to_stream(subscription_name, subscriber, opts) do
    {start_from, opts} = Keyword.pop(opts, :start_from, :origin)

    opts = Keyword.merge([start_from_event_id: start_from_event_id(start_from)], opts)

    Subscriptions.subscribe_to_all_streams(subscription_name, subscriber, opts)
  end

  defp start_from_event_id(:origin), do: 0
  defp start_from_event_id(:current), do: -1
  defp start_from_event_id(start_from) when is_integer(start_from), do: start_from

  defp read_storage_forward(start_event_id, count, serializer) do
    case Storage.read_all_streams_forward(start_event_id, count) do
      {:ok, recorded_events} -> {:ok, Enum.map(recorded_events, &RecordedEvent.deserialize(&1, serializer))}
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
end
