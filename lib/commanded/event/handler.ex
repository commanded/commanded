defmodule Commanded.Event.Handler do
  use GenServer
  require Logger

  alias Commanded.Event.Handler

  @type domain_event :: struct
  @type metadata :: struct

  @doc """
  Event handler behaviour to handle a domain event and its metadata
  """
  @callback handle(domain_event, metadata) :: :ok | {:error, reason :: atom}

  defstruct handler_name: nil, handler_module: nil, last_seen_event_id: nil

  def start_link(handler_name, handler_module) do
    GenServer.start_link(__MODULE__, %Handler{
      handler_name: handler_name,
      handler_module: handler_module
    })
  end

  def init(%Handler{} = state) do
    GenServer.cast(self, {:subscribe_to_events})
    {:ok, state}
  end

  def handle_cast({:subscribe_to_events}, %Handler{handler_name: handler_name} = state) do
    {:ok, _} = EventStore.subscribe_to_all_streams(handler_name, self)
    {:noreply, state}
  end

  def handle_info({:events, events, subscription}, state) do
    Logger.debug(fn -> "event handler received events: #{inspect events}" end)

    state = Enum.reduce(events, state, fn (event, state) ->
      case handle_event(event, state) do
        {:ok, event_id} -> confirm_receipt(state, subscription, event_id)
        {:error, :already_seen_event} -> state
      end
    end)

    {:noreply, state}
  end

  # ignore already seen events
  defp handle_event(%EventStore.RecordedEvent{event_id: event_id} = event, %Handler{last_seen_event_id: last_seen_event_id}) when not is_nil(last_seen_event_id) and event_id <= last_seen_event_id do
    Logger.debug(fn -> "event handler has already seen event: #{inspect event}" end)
    {:error, :already_seen_event}
  end

  # delegate event to handler module
  defp handle_event(%EventStore.RecordedEvent{event_id: event_id, data: data, metadata: metadata}, %Handler{handler_module: handler_module}) do
    case handler_module.handle(data, Map.merge(%{event_id: event_id}, metadata)) do
      :ok -> {:ok, event_id}
      {:error, _reason} = reply -> reply
    end
  end

  # confirm receipt of event
  defp confirm_receipt(state, subscription, event_id) do
    Logger.debug(fn -> "event handler confirming receipt of event: #{event_id}" end)

    send(subscription, {:ack, event_id})

    %Handler{state | last_seen_event_id: event_id}
  end
end
