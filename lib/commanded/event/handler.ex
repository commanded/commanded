defmodule Commanded.Event.Handler do
  use Commanded.EventStore
  use GenServer
  require Logger

  alias Commanded.Event.Handler
  alias Commanded.EventStore.RecordedEvent
  
  @type domain_event :: struct
  @type metadata :: struct
  @type subscribe_from :: :origin | :current | non_neg_integer

  @doc """
  Event handler behaviour to handle a domain event and its metadata
  """
  @callback handle(domain_event, metadata) :: :ok | {:error, reason :: atom}

  defstruct [
    handler_name: nil,
    handler_module: nil,
    last_seen_stream_version: nil,
    subscribe_from: nil,
  ]

  def start_link(handler_name, handler_module, opts \\ []) do
    GenServer.start_link(__MODULE__, %Handler{
      handler_name: handler_name,
      handler_module: handler_module,
      subscribe_from: opts[:start_from] || :origin,
    })
  end

  def init(%Handler{} = state) do
    GenServer.cast(self(), {:subscribe_to_events})
    {:ok, state}
  end

  def handle_cast({:subscribe_to_events}, %Handler{handler_name: handler_name, subscribe_from: subscribe_from} = state) do
    {:ok, _} = @event_store.subscribe_to_all_streams(handler_name, self(), subscribe_from)
    {:noreply, state}
  end

  def handle_info({:events, events, subscription}, state) do
    Logger.debug(fn -> "event handler received events: #{inspect events}" end)

    state = Enum.reduce(events, state, fn (event, state) ->
      stream_version = extract_stream_version(event)
      data = extract_data(event)
      metadata = extract_metadata(event)

      case handle_event(stream_version, data, metadata, state) do
        :ok -> confirm_receipt(state, subscription, stream_version)
        {:error, :already_seen_event} -> state
      end
    end)

    {:noreply, state}
  end

  defp extract_stream_version(%RecordedEvent{stream_version: stream_version}), do: stream_version
  defp extract_data(%RecordedEvent{data: data}), do: data
  defp extract_metadata(%RecordedEvent{event_id: event_id, stream_id: stream_id, stream_version: stream_version, metadata: metadata, created_at: created_at}) do
    Map.merge(%{event_id: event_id, stream_id: stream_id, stream_version: stream_version, created_at: created_at}, metadata)
  end

  # ignore already seen events
  defp handle_event(stream_version, _data, _metadata, %Handler{last_seen_stream_version: last_seen_stream_version}) when not is_nil(last_seen_stream_version) and stream_version <= last_seen_stream_version do
    Logger.debug(fn -> "event handler has already seen event id: #{inspect stream_version}" end)
    {:error, :already_seen_event}
  end

  # delegate event to handler module
  defp handle_event(_stream_version, data, metadata, %Handler{handler_module: handler_module}) do
    handler_module.handle(data, metadata)
  end

  # confirm receipt of event
  defp confirm_receipt(state, subscription, stream_version) do
    Logger.debug(fn -> "event handler confirming receipt of event: #{stream_version}" end)

    send(subscription, {:ack, stream_version})
 
    %Handler{state | last_seen_stream_version: stream_version}
  end
end
