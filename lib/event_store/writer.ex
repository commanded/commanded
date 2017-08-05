defmodule EventStore.Writer do
  @moduledoc """
  Single process writer to assign a monotonically increasing id and persist events to the store
  """

  alias EventStore.{Subscriptions,RecordedEvent}
  alias EventStore.Storage

  @doc """
  Append the given list of recorded events to the stream

  Returns `:ok` on success, or `{:error, reason}` on failure
  """
  @spec append_to_stream(list(RecordedEvent.t), String.t, EventStore.Serializer.t) :: :ok | {:error, reason :: any()}
  def append_to_stream(events, stream_uuid, serializer)
  def append_to_stream([], _stream_uuid, _serializer), do: :ok
  def append_to_stream(events, stream_uuid, serializer) do
    case Storage.append_to_stream(events) do
      {:ok, assigned_event_ids} ->
        events
        |> assign_event_ids(assigned_event_ids)
        |> publish_events(stream_uuid, serializer)

        :ok

      {:error, _reason} = reply -> reply
    end
  end

  defp assign_event_ids(events, ids) do
    events
    |> Enum.zip(ids)
    |> Enum.map(fn {event, id} ->
      %RecordedEvent{event | event_id: id}
    end)
  end

  defp publish_events(events, stream_uuid, serializer) do
    Subscriptions.notify_events(stream_uuid, events, serializer)
  end
end
