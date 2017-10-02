defmodule EventStore.Writer do
  @moduledoc false

  alias EventStore.{
    RecordedEvent,
    Registration,
    Storage,
  }

  @doc """
  Append the given list of recorded events to the stream.

  Returns `:ok` on success, or `{:error, reason}` on failure
  """
  @spec append_to_stream(events :: list(RecordedEvent.t), stream_id :: non_neg_integer(), stream_uuid :: String.t) :: :ok | {:error, reason :: any()}
  def append_to_stream([], _stream_id, _stream_uuid), do: :ok
  def append_to_stream(events, stream_id, stream_uuid) do
    case Storage.append_to_stream(stream_id, events) do
      {:ok, assigned_event_ids} ->
        events
        |> assign_event_ids(assigned_event_ids)
        |> publish_events(stream_uuid)

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

  defp publish_events(events, stream_uuid), do: Registration.publish_events(stream_uuid, events)
end
