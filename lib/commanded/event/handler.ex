defmodule Commanded.Event.Handler do
  @moduledoc """
  Defines the behaviour an event handler must implement and
  provides a convenience macro that implements the behaviour, allowing you to
  handle only the events you are interested in processing.

  You should start your event handlers using a [Supervisor](supervision.html) to
  ensure they are restarted on error.

  ## Example

      defmodule ExampleHandler do
        use Commanded.Event.Handler, name: "ExampleHandler"

        def handle(%AnEvent{..}, _metadata) do
          # ... process the event
          :ok
        end
      end

  Start your event handler process (or use a [Supervisor](supervision.html)):

      {:ok, _handler} = ExampleHandler.start_link()

  ## Event handler name

  The name you specify is used when subscribing to the event store. Therefore
  you *should not* change the name once the handler has been deployed. A new
  subscription will be created when you change the name, and you event handler
  will receive already handled events.

  You can use the module name of your event handler using the `__MODULE__`
  special form:

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          name: __MODULE__
      end

  ## Subscription options

  You can choose to start the event handler's event store subscription from
  `:origin`, `:current` position, or an exact event number using the
  `start_from` option. The default is to use the origin so your handler will
  receive *all* events.

  Use the `:current` position when you don't want newly created event handlers
  to go through all previous events. An example would be adding an event handler
  to send transactional emails to an already deployed system containing many
  historical events.

  ### Example

  Set the `start_from` option (`:origin`, `:current`, or an explicit event
  number) when using `Commanded.Event.Handler`:

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          name: "ExampleHandler",
          start_from: :origin
      end

  You can optionally override `:start_from` by passing it as option when
  starting your handler:

      {:ok, _handler} = ExampleHandler.start_link(start_from: :current)

  ## `c:init/0` callback

  You can define an `c:init/0` function in your handler to be called when it
  starts. This callback function must return `:ok`, any other return value will
  prevent the handler from starting.

      defmodule ExampleHandler do
        use Commanded.Event.Handler, name: "ExampleHandler"

        def init do
          # optional initialisation
          :ok
        end

        def handle(%AnEvent{..}, _metadata) do
          # ... process the event
          :ok
        end
      end

  ## `c:error/3` callback

  You can define an `c:error/3` callback function to handle any errors returned
  from your event handler's `handle/2` functions. The `c:error/3` function is
  passed the actual error (e.g. `{:error, :failure}`), the failed event, and a
  failure context.

  Use pattern matching on the error and/or failed event to explicitly handle
  certain errors or events. You can choose to retry, skip, or stop the event
  handler after an error.

  The default behaviour if you don't provide an `c:error/3` callback is to stop
  the event handler using the exact error reason returned from the `handle/2`
  function. You should supervise event handlers to ensure they are correctly
  restarted on error.

  ### Example error handling

      defmodule ExampleHandler do
        use Commanded.Event.Handler, name: __MODULE__

        require Logger

        alias Commanded.Event.FailureContext

        def handle(%AnEvent{}, _metadata) do
          # simulate event handling failure
          {:error, :failed}
        end

        def error({:error, :failed}, %AnEvent{} = event, %FailureContext{context: context}) do
          context = record_failure(context)

          case Map.get(context, :failures) do
            too_many when too_many >= 3 ->
              # skip bad event after third failure
              Logger.warn(fn -> "Skipping bad event, too many failures: " <> inspect(event) end)

              :skip

            _ ->
              # retry event, failure count is included in context map
              {:retry, context}
          end
        end

        defp record_failure(context) do
          Map.update(context, :failures, 1, fn failures -> failures + 1 end)
        end
      end

  ## Consistency

  For each event handler you can define its consistency, as one of either
  `:strong` or `:eventual`.

  This setting is used when dispatching commands and specifying the
  `consistency` option.

  When you dispatch a command using `:strong` consistency, after successful
  command dispatch the process will block until all event handlers configured to
  use `:strong` consistency have processed the domain events created by the
  command. This is useful when you have a read model updated by an event handler
  that you wish to query for data affected by the command dispatch. With
  `:strong` consistency you are guaranteed that the read model will be
  up-to-date after the command has successfully dispatched. It can be safely
  queried for data updated by any of the events created by the command.

  The default setting is `:eventual` consistency. Command dispatch will return
  immediately upon confirmation of event persistence, not waiting for any event
  handlers.

  ### Example

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          name: "ExampleHandler",
          consistency: :strong
      end

  """

  use GenServer
  use Commanded.Registration

  require Logger

  alias Commanded.Event.{FailureContext, Handler}
  alias Commanded.EventStore
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Subscriptions

  @type domain_event :: struct()
  @type metadata :: map()
  @type subscribe_from :: :origin | :current | non_neg_integer()
  @type consistency :: :eventual | :strong

  @doc """
  Optional initialisation callback function called when the handler starts.

  Can be used to start any related processes when the event handler is started.

  Return `:ok` on success, or `{:stop, reason}` to stop the handler process.
  """
  @callback init() :: :ok | {:stop, reason :: any()}

  @doc """
  Event handler behaviour to handle a domain event and its metadata.

  Return `:ok` on success, `{:error, :already_seen_event}` to ack and skip the
  event, or `{:error, reason}` on failure.
  """
  @callback handle(domain_event, metadata) :: :ok
    | {:error, :already_seen_event}
    | {:error, reason :: any()}

  @doc """
  Called when an event `handle/2` callback returns an error.

  The `c:error/3` function allows you to control how event handling failures
  are handled. The function is passed the error returned by the event handler
  (e.g. `{:error, :failure}`), the event causing the error, and a context map
  containing state passed between retries. Use the context map to track any
  transient state you need to access between retried failures.

  You can return one of the following responses depending upon the
  error severity:

  - `{:retry, context}` - retry the failed event, provide a context
    map containing any state passed to subsequent failures. This could be used
    to count the number of failures, stopping after too many.

  - `{:retry, delay, context}` - retry the failed event, after sleeping for
    the requested delay (in milliseconds). Context is a map as described in
    `{:retry, context}` above.

  - `:skip` - skip the failed event by acknowledging receipt.

  - `{:stop, reason}` - stop the event handler with the given reason.

  """
  @callback error(error :: term(), failed_event :: domain_event, failure_context :: FailureContext.t()) :: {:retry, context :: map()}
    | {:retry, delay :: non_neg_integer(), context :: map()}
    | :skip
    | {:stop, reason :: term()}

  @doc """
  Macro as a convenience for defining an event handler.
  """
  defmacro __using__(opts) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)

      @behaviour Commanded.Event.Handler

      @opts unquote(opts) || []
      @name Commanded.Event.Handler.parse_name(__MODULE__, @opts[:name])

      @doc false
      def start_link(opts \\ []) do
        opts = Commanded.Event.Handler.start_opts(__MODULE__, Keyword.drop(@opts, [:name]), opts)

        Commanded.Event.Handler.start_link(@name, __MODULE__, opts)
      end

      @doc """
      Provides a child specification to allow the event handler to be easily
      supervised.

      ## Example

          Supervisor.start_link([
            {ExampleHandler, []}
          ], strategy: :one_for_one)

      """
      def child_spec(opts) do
        default = %{
          id: {__MODULE__, @name},
          start: {__MODULE__, :start_link, [opts]},
          restart: :permanent,
          type: :worker,
        }

        Supervisor.child_spec(default, [])
      end

      @doc false
      def init, do: :ok

      defoverridable [init: 0]
    end
  end

  @doc false
  def parse_name(module, name) when name in [nil, ""], do: raise "#{inspect module} expects `:name` to be given"
  def parse_name(_module, name) when is_bitstring(name), do: name
  def parse_name(_module, name), do: inspect(name)

  @doc false
  def start_opts(module, module_opts, local_opts) do
    {valid, invalid} =
      module_opts
      |> Keyword.merge(local_opts)
      |> Keyword.split([:consistency, :start_from])

    if Enum.any?(invalid) do
      raise "#{inspect module} specifies invalid options: #{inspect Keyword.keys(invalid)}"
    else
      valid
    end
  end

  # Include default `handle/2` and `error/3` callback functions in module

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def handle(_event, _metadata), do: :ok

      @doc false
      def error({:error, reason}, _failed_event, _failure_context), do: {:stop, reason}
    end
  end

  @doc false
  defstruct [
    :consistency,
    :handler_name,
    :handler_module,
    :last_seen_event,
    :subscribe_from,
    :subscription
  ]

  @doc false
  def start_link(handler_name, handler_module, opts \\ []) do
    name = name(handler_name)
    handler = %Handler{
      handler_name: handler_name,
      handler_module: handler_module,
      consistency: opts[:consistency] || Application.get_env(:commanded, :default_consistency, :eventual),
      subscribe_from: opts[:start_from] || :origin,
    }

    Registration.start_link(name, __MODULE__, handler)
  end

  @doc false
  def name(name), do: {__MODULE__, name}

  @doc false
  def init(%Handler{handler_module: handler_module} = state) do
    GenServer.cast(self(), :subscribe_to_events)

    reply =
      case handler_module.init() do
        :ok -> :ok
        {:stop, _reason} = reply -> reply
      end

    {reply, state}
  end

  @doc false
  def handle_call(:last_seen_event, _from, %Handler{last_seen_event: last_seen_event} = state) do
    {:reply, last_seen_event, state}
  end

  @doc false
  def handle_call(:config, _from, %Handler{consistency: consistency, subscribe_from: subscribe_from} = state) do
    {:reply, [consistency: consistency, start_from: subscribe_from], state}
  end

  @doc false
  def handle_cast(:subscribe_to_events, %Handler{} = state) do
    {:noreply, subscribe_to_all_streams(state)}
  end

  @doc false
  def handle_info({:events, events}, %Handler{} = state) do
    Logger.debug(fn -> describe(state) <> " received events: #{inspect events}" end)

    try do
      state = Enum.reduce(events, state, &handle_event/2)

      {:noreply, state}
    catch
      {:error, reason} ->
        # stop after event handling returned an error
        {:stop, reason, state}
    end
  end

  defp subscribe_to_all_streams(%Handler{} = state) do
    %Handler{
      consistency: consistency,
      handler_name: handler_name,
      subscribe_from: subscribe_from
    } = state

    {:ok, subscription} = EventStore.subscribe_to_all_streams(handler_name, self(), subscribe_from)

    # register this event handler as a subscription with the given consistency
    :ok = Subscriptions.register(handler_name, consistency)

    %Handler{state | subscription: subscription}
  end

  defp handle_event(event, handler, context \\ %{})

  # ignore already seen events
  defp handle_event(%RecordedEvent{event_number: event_number} = event, %Handler{last_seen_event: last_seen_event} = state, _context)
    when not is_nil(last_seen_event) and event_number <= last_seen_event
  do
    Logger.debug(fn -> describe(state) <> " has already seen event ##{inspect event_number}" end)

    confirm_receipt(event, state)
  end

  # delegate event to handler module
  defp handle_event(%RecordedEvent{data: data} = event, %Handler{handler_module: handler_module} = state, context) do
    case handler_module.handle(data, enrich_metadata(event)) do
      :ok ->
        confirm_receipt(event, state)

      {:error, :already_seen_event} ->
        confirm_receipt(event, state)

      {:error, reason} = error ->
        Logger.error(fn -> describe(state) <> " failed to handle event #{inspect event} due to: #{inspect reason}" end)

        handle_event_error(error, event, state, context)
    end
  end

  defp handle_event_error(error, %RecordedEvent{} = failed_event, %Handler{} = state, context) do
    %RecordedEvent{data: data} = failed_event
    %Handler{handler_module: handler_module} = state

    failure_context = %FailureContext{
      context: context,
      metadata: enrich_metadata(failed_event)
    }

    case handler_module.error(error, data, failure_context) do
      {:retry, context} when is_map(context) ->
        # retry the failed event
        Logger.info(fn -> describe(state) <> " is retrying failed event" end)

        handle_event(failed_event, state, context)

      {:retry, delay, context} when is_map(context) and is_integer(delay) and delay >= 0 ->
        # retry the failed event after waiting for the given delay, in milliseconds
        Logger.info(fn -> describe(state) <> " is retrying failed event after #{inspect delay}ms" end)

        :timer.sleep(delay)

        handle_event(failed_event, state, context)

      :skip ->
        # skip the failed event by confirming receipt
        Logger.info(fn -> describe(state) <> " is skipping event" end)

        confirm_receipt(failed_event, state)

      {:stop, reason} ->
        # stop event handler
        Logger.warn(fn -> describe(state) <> " has requested to stop: #{inspect reason}" end)

        throw({:error, reason})

       invalid ->
         Logger.warn(fn -> describe(state) <> " returned an invalid error reponse: #{inspect invalid}" end)

         # stop event handler with original error
         throw(error)
    end
  end

  # confirm receipt of event
  defp confirm_receipt(%RecordedEvent{event_number: event_number} = event, %Handler{} = state) do
    Logger.debug(fn -> describe(state) <> " confirming receipt of event ##{inspect event_number}" end)

    ack_event(event, state)

    %Handler{state | last_seen_event: event_number}
  end

  defp ack_event(event, %Handler{consistency: consistency, handler_name: handler_name, subscription: subscription}) do
    :ok = EventStore.ack_event(subscription, event)
    :ok = Subscriptions.ack_event(handler_name, consistency, event)
  end

  @enrich_metadata_fields [
    :event_id,
    :event_number,
    :stream_id,
    :stream_version,
    :correlation_id,
    :causation_id,
    :created_at,
  ]

  defp enrich_metadata(%RecordedEvent{metadata: metadata} = event) do
    event
    |> Map.from_struct()
    |> Map.take(@enrich_metadata_fields)
    |> Map.merge(metadata || %{})
  end

  defp describe(%Handler{handler_module: handler_module}),
    do: inspect(handler_module)
end
