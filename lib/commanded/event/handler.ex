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
    last_seen_event_id: nil,
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
    GenServer.cast(self, {:subscribe_to_events})
    {:ok, state}
  end

  def handle_cast({:subscribe_to_events}, %Handler{handler_name: handler_name, subscribe_from: subscribe_from} = state) do
    {:ok, _} = @event_store.subscribe_to_all_streams(handler_name, self, subscribe_from)
    {:noreply, state}
  end

  def handle_info({:events, events, subscription}, state) do
    Logger.debug(fn -> "event handler received events: #{inspect events}" end)

    state = Enum.reduce(events, state, fn (event, state) ->
      event_id = extract_event_id(event)
      data = extract_data(event)
      metadata = extract_metadata(event)

      case handle_event(event_id, data, metadata, state) do
        :ok -> confirm_receipt(state, subscription, event_id)
        {:error, :already_seen_event} -> state
      end
    end)

    {:noreply, state}
  end

  defp extract_event_id(%RecordedEvent{event_id: event_id}), do: event_id
  defp extract_data(%RecordedEvent{data: data}), do: data
  defp extract_metadata(%RecordedEvent{event_id: event_id, metadata: metadata, created_at: created_at}) do
    Map.merge(%{event_id: event_id, created_at: created_at}, metadata)
  end

  # ignore already seen events
  defp handle_event(event_id, _data, _metadata, %Handler{last_seen_event_id: last_seen_event_id}) when not is_nil(last_seen_event_id) and event_id <= last_seen_event_id do
    Logger.debug(fn -> "event handler has already seen event id: #{inspect event_id}" end)
    {:error, :already_seen_event}
  end

  # delegate event to handler module
  defp handle_event(_event_id, data, metadata, %Handler{handler_module: handler_module}) do
    handler_module.handle(data, metadata)
  end

  # confirm receipt of event
  defp confirm_receipt(state, subscription, event_id) do
    Logger.debug(fn -> "event handler confirming receipt of event: #{event_id}" end)

    send(subscription, {:ack, event_id})
 
    %Handler{state | last_seen_event_id: event_id}
  end
end
