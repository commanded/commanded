defmodule Commanded.Event.Handler do
  @moduledoc """
  Defines the behaviour an event handler must implement.

  Provides a convenience macro that implements the behaviour, allowing you to handle only the events you are interested in processing.

  You should start your event handlers using a [Supervisor](supervision.html) to ensure they are restarted on error.

  # Event handler name

  The name you specify is used when subscribing to the event store.
  Therefore you *should not* change the name once the handler has been deployed.
  A new subscription will be created when you change the name, and you event handler will receive already handled events.

  # Subscription options

  You can choose to start the event handler's event store subscription from `:origin`, `:current` position, or an exact event number using the `start_from` option.
  The default is to use the origin so your handler will receive *all* events.

  Use the `:current` position when you don't want newly created event handlers to go through all previous events.
  An example would be adding an event handler to send transactional emails to an already deployed system containing many historical events.

  ## Example

  Set the `start_from` option (`:origin`, `:current`, or an explicit event number) when using `Commanded.Event.Handler`:

      defmodule AccountBalanceHandler do
        use Commanded.Event.Handler, name: "AccountBalanceHandler", start_from: :origin

        # ...
      end

  You can optionally override `:start_from` by passing it as option when starting your handler:

      {:ok, _handler} = AccountBalanceHandler.start_link(start_from: :current)

  """

  use GenServer

  require Logger

  alias Commanded.Event.Handler
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent

  @type domain_event :: struct
  @type metadata :: struct
  @type subscribe_from :: :origin | :current | non_neg_integer

  @doc """
  Event handler behaviour to handle a domain event and its metadata

  Return `:ok` on success, `{:error, :already_seen_event}` to ack and skip the event, or `{:error, reason}` on failure.
  """
  @callback handle(domain_event, metadata) :: :ok | {:error, reason :: atom}

  @doc """
  Macro as a convenience for defining an event handler

  ## Example

    defmodule ExampleHandler do
      use Commanded.Event.Handler, name: "ExampleHandler"

      def handle(%AnEvent{...}, _metadata) do
        # ...
      end
    end

  Start event handler process (or configure as a worker inside a [supervisor](supervision.html)):

    {:ok, handler} = ExampleHandler.start_link()
  """
  defmacro __using__(opts) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)

      @behaviour Commanded.Event.Handler

      @opts unquote(opts) || []
      @name @opts[:name] || raise "#{inspect __MODULE__} expects :name to be given"

      def start_link(opts \\ []) do
        opts =
          @opts
          |> Keyword.take([:start_from])
          |> Keyword.merge(opts)

        Commanded.Event.Handler.start_link(@name, __MODULE__, opts)
      end
    end
  end

  # include default fallback function at end, with lowest precedence
  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def handle(_event, _metadata), do: :ok
    end
  end

  defstruct [
    handler_name: nil,
    handler_module: nil,
    last_seen_event: nil,
    subscribe_from: nil,
    subscription: nil,
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
    {:ok, subscription} = EventStore.subscribe_to_all_streams(handler_name, self(), subscribe_from)

    state = %Handler{state |
      subscription: subscription,
    }

    {:noreply, state}
  end

  def handle_info({:events, events}, state) do
    Logger.debug(fn -> "event handler received events: #{inspect events}" end)

    state = Enum.reduce(events, state, fn (event, state) ->
      event_number = extract_event_number(event)
      data = extract_data(event)
      metadata = extract_metadata(event)

      case handle_event(event_number, data, metadata, state) do
        :ok -> confirm_receipt(event, state)
        {:error, :already_seen_event} -> state
      end
    end)

    {:noreply, state}
  end

  # ignore already seen events
  defp handle_event(event_number, _data, _metadata, %Handler{last_seen_event: last_seen_event})
    when not is_nil(last_seen_event) and event_number <= last_seen_event
  do
    Logger.debug(fn -> "event handler has already seen event: #{inspect event_number}" end)
    {:error, :already_seen_event}
  end

  # delegate event to handler module
  defp handle_event(_event_number, data, metadata, %Handler{handler_module: handler_module}) do
    handler_module.handle(data, metadata)
  end

  # confirm receipt of event
  defp confirm_receipt(%RecordedEvent{event_number: event_number} = event, %Handler{subscription: subscription} = state) do
    Logger.debug(fn -> "event handler confirming receipt of event: #{inspect event_number}" end)

    EventStore.ack_event(subscription, event)

    %Handler{state | last_seen_event: event_number}
  end

  defp extract_event_number(%RecordedEvent{event_number: event_number}), do: event_number

  defp extract_data(%RecordedEvent{data: data}), do: data

  defp extract_metadata(%RecordedEvent{metadata: nil} = event), do: extract_metadata(%RecordedEvent{event | metadata: %{}})
  defp extract_metadata(%RecordedEvent{event_number: event_number, stream_id: stream_id, stream_version: stream_version, metadata: metadata, created_at: created_at}) do
    Map.merge(%{event_number: event_number, stream_id: stream_id, stream_version: stream_version, created_at: created_at}, metadata)
  end
end
