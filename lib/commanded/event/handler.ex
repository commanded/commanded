defmodule Commanded.Event.Handler do
  use GenServer
  use Commanded.Registration
  use TelemetryRegistry

  telemetry_event(%{
    event: [:commanded, :event, :handle, :start],
    description: "Emitted when an event handler starts handling an event",
    measurements: "%{system_time: integer()}",
    metadata: """
    %{application: Commanded.Application.t(),
      context: map(),
      handler_name: String.t(),
      handler_module: atom(),
      handler_state: map(),
      recorded_event: RecordedEvent.t()}
    """
  })

  telemetry_event(%{
    event: [:commanded, :event, :handle, :stop],
    description: "Emitted when an event handler stops handling an event",
    measurements: "%{duration: non_neg_integer()}",
    metadata: """
    %{:application => Commanded.Application.t(),
      :context => map(),
      :handler_name => String.t(),
      :handler_module => atom(),
      :handler_state => map(),
      :recorded_event => RecordedEvent.t(),
      optional(:error) => any()}
    """
  })

  telemetry_event(%{
    event: [:commanded, :event, :handle, :exception],
    description: "Emitted when an event handler raises an exception",
    measurements: "%{duration: non_neg_integer()}",
    metadata: """
    %{application: Commanded.Application.t(),
      context: map(),
      handler_name: String.t(),
      handler_module: atom(),
      handler_state: map(),
      recorded_event: RecordedEvent.t(),
      kind: :throw | :error | :exit,
      reason: any(),
      stacktrace: list()}
    """
  })

  @moduledoc """
  Defines the behaviour an event handler must implement and
  provides a convenience macro that implements the behaviour, allowing you to
  handle only the events you are interested in processing.

  You should start your event handlers using a [Supervisor](supervision.html) to
  ensure they are restarted on error.

  ### Example

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          application: ExampleApp,
          name: "ExampleHandler"

        def handle(%AnEvent{..}, _metadata) do
          # ... process the event
          :ok
        end
      end

  Start your event handler process (or use a [Supervisor](supervision.html)):

      {:ok, _handler} = ExampleHandler.start_link()

  ## Event handler name

  The name you specify is used when subscribing to the event store. You must use
  a unique name for each event handler and process manager you start. Also, you
  *should not* change the name once the handler has been deployed. A new
  subscription will be created if you change the name and the event handler will
  receive already handled events.

  You can use the module name of your event handler using the `__MODULE__`
  special form:

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          application: ExampleApp,
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

  The `start_from` option *only applies* when the subscription is initially
  created, the first time the handler starts. Whenever the handler restarts the
  subscription will resume from the next event after the last successfully
  processed event. Restarting an event handler does not restart its
  subscription.

  ### Example

  Set the `start_from` option (`:origin`, `:current`, or an explicit event
  number) when using `Commanded.Event.Handler`:

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          application: ExampleApp,
          name: "ExampleHandler",
          start_from: :origin
      end

  You can optionally override `:start_from` by passing it as option when
  starting your handler:

      {:ok, _handler} = ExampleHandler.start_link(start_from: :current)

  ### Subscribing to an individual stream

  By default event handlers will subscribe to all events appended to any stream.
  Provide a `subscribe_to` option to subscribe to a single stream.

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          application: ExampleApp,
          name: __MODULE__,
          subscribe_to: "stream1234"
      end

  This will ensure the handler only receives events appended to that stream.

  ## Runtime event handler configuration

  Runtime options can be provided to the event handler's `start_link/1` function
  or its child spec. The `c:init/1` callback function can also be used to define
  runtime configuration.

  ### Example

  Provide runtime configuration to `start_link/1`:

      {:ok, _pid} =
        ExampleHandler.start_link(
          application: ExampleApp,
          name: "ExampleHandler"
        )

  Or when supervised:

      Supervisor.start_link([
        {ExampleHandler, application: ExampleApp, name: "ExampleHandler"}
      ], strategy: :one_for_one)

  ## Event handler state

  An event handler can define and update state which is held in the `GenServer`
  process memory. It is passed to the `handle/2` function as part of the
  metadata using the `:state` key. The state is transient and will be lost
  whenever the process restarts.

  Initial state can be set in the `init/1` callback function by adding a
  `:state` key to the config. It can also be provided when starting the handler
  process:

      ExampleHandler.start_link(state: initial_state)

  Or when supervised:

      Supervisor.start_link([
        {ExampleHandler, state: initial_state}
      ], strategy: :one_for_one)

  State can be updated by returning `{:ok, new_state}` from any `handle/2`
  function. Returning an `:ok` reply will keep the state unchanged.

  Handler state is also included in the `Commanded.Event.FailureContext` struct
  passed to the `error/3` callback function.

  ### Example

      defmodule StatefulEventHandler do
        use Commanded.Event.Handler,
          application: ExampleApp,
          name: __MODULE__

        def init(config) do
          config = Keyword.put_new(config, :state, %{})

          {:ok, config}
        end

        def handle(event, metadata) do
          %{state: state} = metadata

          new_state = mutate_state(state)

          {:ok, new_state}
        end
      end

  ## Concurrency

  An event handler may be configured to start multiple processes to handle the
  events concurrently. By default one process will be started, processing events
  one at a time in order. The `:concurrency` option determines how many event
  handler processes are started. It must be a positive integer.

  Note with concurrent processing events will likely by processed out of order.
  If you need to enforce an order, such as per stream or by using a field from
  an event, you can define a `c:partition_by/2` callback function in the event
  handler module. The function will receive each event and its metadata and must
  return a consistent term indicating the event's partition. Events which return
  the same term are guaranteed to be processed in order by the same event
  handler instance. While events with different partitions may be processed
  concurrently by another instance. An attempt will be made to distribute
  events as evenly as possible to all running event handler instances.

  Only `:eventual` consistency is supported when multiple handler processes are
  configured with a `:concurrency` of greater than one.

  ### Example

      defmodule ConcurrentProcssingEventHandler do
        alias Commanded.EventStore.RecordedEvent

        use Commanded.Event.Handler,
          application: ExampleApp,
          name: __MODULE__,
          concurrency: 10

        def init(config) do
          # Fetch the index of this event handler instance (0..9 in this example)
          index = Keyword.fetch!(config, :index)

          {:ok, config}
        end

        def handle(event, metadata) do
          :ok
        end

        # Partition events by their stream
        def partition_by(event, metadata) do
          %{stream_id: stream_id} = metadata

          stream_id
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

  Note strong consistency does not imply a transaction covers the command
  dispatch and event handling. It only guarantees that the event handler will
  have processed all events produced by the command: if event handling fails
  the events will have still been persisted.

  ### Example

  Define an event handler with `:strong` consistency:

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          application: ExampleApp,
          name: "ExampleHandler",
          consistency: :strong
      end

  ## Dynamic application

  An event handler's application can be provided as an option to `start_link/1`.
  This can be used to start the same handler multiple times, each using a
  separate Commanded application and event store.

  ### Example

  Start an event handler process for each tenant in a multi-tenanted app,
  guaranteeing that the data and processing remains isolated between tenants.

      for tenant <- [:tenant1, :tenant2, :tenant3] do
        {:ok, _app} = MyApp.Application.start_link(name: tenant)
        {:ok, _handler} = ExampleHandler.start_link(application: tenant)
      end

  Typically you would start the event handlers using a supervisor:

      children =
        for tenant <- [:tenant1, :tenant2, :tenant3] do
          {ExampleHandler, application: tenant}
        end

      Supervisor.start_link(children, strategy: :one_for_one)

  The above example requires three named Commanded applications to have already
  been started.

  ## Telemetry

  #{telemetry_docs()}

  """

  require Logger

  alias Commanded.Event.FailureContext
  alias Commanded.Event.Handler
  alias Commanded.Event.Upcast
  alias Commanded.EventStore.RecordedEvent
  alias Commanded.EventStore.Subscription
  alias Commanded.Subscriptions
  alias Commanded.Telemetry

  @type domain_event :: struct()
  @type metadata :: map()
  @type subscribe_from :: :origin | :current | non_neg_integer()
  @type consistency :: :eventual | :strong

  @doc """
  Optional initialisation callback function called when the handler starts.

  Can be used to start any related processes when the event handler is started.

  This callback function must return `:ok`, or `{:stop, reason}` to stop the
  handler process. Any other return value will terminate the event handler with
  an error.

  ### Example

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          application: ExampleApp,
          name: "ExampleHandler"

        # Optional initialisation
        def init do
          :ok
        end

        def handle(%AnEvent{..}, _metadata) do
          # Process the event ...
          :ok
        end
      end

  """
  @callback init() :: :ok | {:stop, reason :: any()}

  @doc """
  Optional callback function called to configure the handler before it starts.

  It is passed the merged compile-time and runtime config, and must return the
  updated config as `{:ok, config}`.

  Note this function is called before the event handler process is started and
  *is not* run from the handler's process. You cannot use `self()` to access the
  handler's PID.

  ### Example

  The `c:init/1` function is used to define the handler's application and name
  based upon a value provided at runtime:

      defmodule ExampleHandler do
        use Commanded.Event.Handler

        def init(config) do
          {tenant, config} = Keyword.pop!(config, :tenant)

          config =
            config
            |> Keyword.put(:application, Module.concat([ExampleApp, tenant]))
            |> Keyword.put(:name, Module.concat([__MODULE__, tenant]))

          {:ok, config}
        end
      end

  Usage:

      {:ok, _pid} = ExampleHandler.start_link(tenant: :tenant1)

  """
  @callback init(config :: Keyword.t()) :: {:ok, Keyword.t()}

  @doc """
  Handle a domain event and its metadata.

  Return `:ok` on success, `{:error, :already_seen_event}` to ack and skip the
  event, or `{:error, reason}` on failure.
  """
  @callback handle(domain_event, metadata) ::
              :ok
              | {:ok, new_state :: any()}
              | {:error, :already_seen_event}
              | {:error, reason :: any()}

  @doc """
  Called when an event `handle/2` callback returns an error.

  The `c:error/3` function allows you to control how event handling failures
  are handled. The function is passed the error returned by the event handler
  (e.g. `{:error, :failure}`), the event causing the error, and a context map
  containing state passed between retries.

  Use pattern matching on the error and/or failed event to explicitly handle
  certain errors or events. Use the context map to track any transient state you
  need to access between retried failures.

  You can return one of the following responses depending upon the
  error severity:

  - `{:retry, context}` - retry the failed event, provide a context
    map, or updated `Commanded.Event.FailureContext` struct, containing any
    state to be passed to subsequent failures. This could be used to count the
    number of failures, stopping after too many.

  - `{:retry, delay, context}` - retry the failed event, after sleeping for
    the requested delay (in milliseconds). Context is a map or
    `Commanded.Event.FailureContext` struct as described in `{:retry, context}`
    above.

  - `:skip` - skip the failed event by acknowledging receipt.

  - `{:stop, reason}` - stop the event handler with the given reason.

  The default behaviour if you don't provide an `c:error/3` callback is to stop
  the event handler using the exact error reason returned from the `handle/2`
  function. If the event handler is supervised using restart `permanent` or
  `transient` stopping on error will cause the handler to be restarted. It will
  likely crash again as it will reprocesse the problematic event. This can lead
  to cascading failures going up the supervision tree.

  ### Example error handling

      defmodule ExampleHandler do
        use Commanded.Event.Handler,
          application: ExampleApp,
          name: __MODULE__

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

  """
  @callback error(
              error :: term(),
              failed_event :: domain_event,
              failure_context :: FailureContext.t()
            ) ::
              {:retry, context :: map() | FailureContext.t()}
              | {:retry, delay :: non_neg_integer(), context :: map() | FailureContext.t()}
              | :skip
              | {:stop, reason :: term()}

  @doc """
  Determine which partition an event belongs to.

  Only applicable when an event handler has been configured with more than one
  instance via the `:concurrency` option.
  """
  @callback partition_by(domain_event, metadata) :: any()

  @optional_callbacks init: 0, init: 1, error: 3, partition_by: 2

  defmacro __using__(using_opts) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)
      @behaviour Handler

      @doc """
      Start an event handler `GenServer` process linked to the current process.

      ## Options

        - `:application` - the Commanded application.

        - `:name` - name of the event handler used to determine its unique event
          store subscription.

        - `:concurrency` - determines how many processes are started to
          concurrently process events. The default is one process.

        - `:consistency` - one of either `:eventual` (default) or `:strong`.

        - `:start_from` - where to start the event store subscription from when
          first created (default: `:origin`).

        - :subscribe_to - which stream to subscribe to can be either `:all` to
          subscribe to all events or a named stream (default: `:all`).

      The default options supported by `GenServer.start_link/3` are supported,
      including the `:hibernate_after` option which allows the process to go
      into hibernation after a period of inactivity.
      """
      def start_link(opts \\ []) do
        opts = Keyword.merge(unquote(using_opts), opts)

        {application, name, config} = Handler.parse_config!(__MODULE__, opts)

        Handler.start_link(application, name, __MODULE__, config)
      end

      @doc """
      Provides a child specification to allow the event handler to be easily
      supervised.

      Supports the same options as `start_link/3`.

      The default options supported by `GenServer.start_link/3` are also
      supported, including the `:hibernate_after` option which allows the
      process to go into hibernation after a period of inactivity.

      ### Example

          Supervisor.start_link([
            {ExampleHandler, []}
          ], strategy: :one_for_one)

      """
      def child_spec(opts) do
        opts = Keyword.merge(unquote(using_opts), opts)

        spec =
          case Keyword.get(opts, :concurrency, 1) do
            1 ->
              %{
                id: {__MODULE__, opts},
                start: {__MODULE__, :start_link, [opts]},
                restart: :permanent,
                type: :worker
              }

            concurrency when is_integer(concurrency) and concurrency > 1 ->
              opts = Keyword.put(opts, :module, __MODULE__)

              Handler.Supervisor.child_spec(opts)

            invalid ->
              raise ArgumentError,
                    "invalid `:concurrency` for event handler, expected a positive integer but got: " <>
                      inspect(invalid)
          end

        Supervisor.child_spec(spec, [])
      end

      @doc false
      def init, do: :ok

      @doc false
      def init(config), do: {:ok, config}

      @doc false
      def before_reset, do: :ok

      defoverridable init: 0, init: 1, before_reset: 0
    end
  end

  # GenServer start options
  @start_opts [:debug, :name, :timeout, :spawn_opt, :hibernate_after]

  # Event handler configuration options
  @handler_opts [
    :application,
    :name,
    :concurrency,
    :consistency,
    :index,
    :start_from,
    :subscribe_to,
    :subscription_opts,
    :state
  ]

  @doc false
  def parse_config!(module, config) do
    {:ok, config} = module.init(config)

    {_valid, invalid} = Keyword.split(config, @start_opts ++ @handler_opts)

    if Enum.any?(invalid) do
      raise ArgumentError,
            inspect(module) <> " specifies invalid options: " <> inspect(Keyword.keys(invalid))
    end

    {application, config} = Keyword.pop(config, :application)

    unless application do
      raise ArgumentError, inspect(module) <> " expects :application option"
    end

    {name, config} = Keyword.pop(config, :name)

    unless name = parse_name(name) do
      raise ArgumentError, inspect(module) <> " expects :name option"
    end

    {application, name, config}
  end

  @doc false
  def parse_name(name) when name in [nil, ""], do: nil
  def parse_name(name) when is_binary(name), do: name
  def parse_name(name), do: inspect(name)

  @doc false
  defmacro __before_compile__(_env) do
    # Include default `handle/2` and `error/3` callback functions in module
    quote generated: true do
      @doc false
      def handle(_event, _metadata), do: :ok

      @doc false
      def error({:error, reason}, _failed_event, _failure_context), do: {:stop, reason}
    end
  end

  @doc false
  defstruct [
    :application,
    :consistency,
    :handler_name,
    :handler_module,
    :handler_state,
    :last_seen_event,
    :subscription,
    :subscribe_timer
  ]

  @doc false
  def start_link(application, handler_name, handler_module, opts \\ []) do
    {start_opts, handler_opts} = Keyword.split(opts, @start_opts)

    index = Keyword.get(handler_opts, :index)
    name = name(application, handler_name, index)
    consistency = consistency(handler_opts)
    subscription = new_subscription(application, handler_name, handler_module, handler_opts)

    handler = %Handler{
      application: application,
      handler_name: handler_name,
      handler_module: handler_module,
      handler_state: Keyword.get(handler_opts, :state),
      consistency: consistency,
      subscription: subscription
    }

    with {:ok, pid} <- Registration.start_link(application, name, __MODULE__, handler, start_opts) do
      # Register the started event handler as a subscription with the given consistency
      :ok = Subscriptions.register(application, handler_name, handler_module, pid, consistency)

      {:ok, pid}
    end
  end

  @doc false
  def name(application, handler_name, index \\ nil)
  def name(application, handler_name, nil), do: {application, __MODULE__, handler_name}
  def name(application, handler_name, index), do: {application, __MODULE__, handler_name, index}

  @doc false
  @impl GenServer
  def init(%Handler{} = state) do
    Process.flag(:trap_exit, true)

    {:ok, state, {:continue, :subscribe_to_events}}
  end

  @impl GenServer
  def terminate(reason, state) do
    Logger.debug(fn -> describe(state) <> " is shutting down due to #{inspect(reason)}" end)
  end

  @doc false
  @impl GenServer
  def handle_continue(:subscribe_to_events, %Handler{} = state) do
    {:noreply, subscribe_to_events(state)}
  end

  @doc false
  @impl GenServer
  def handle_info(:reset, %Handler{} = state) do
    %Handler{handler_module: handler_module} = state

    case handler_module.before_reset() do
      :ok ->
        try do
          state = state |> reset_subscription() |> subscribe_to_events()

          {:noreply, state}
        catch
          {:error, reason} ->
            {:stop, reason, state}
        end

      {:stop, reason} ->
        Logger.debug(fn ->
          describe(state) <>
            " `before_reset/0` callback has requested to stop. (reason: #{inspect(reason)})"
        end)

        {:stop, reason, state}
    end
  end

  @doc false
  @impl GenServer
  def handle_info(:subscribe_to_events, %Handler{} = state) do
    {:noreply, subscribe_to_events(state)}
  end

  @doc false
  # Subscription to event store has successfully subscribed, init event handler
  @impl GenServer
  def handle_info(
        {:subscribed, subscription},
        %Handler{subscription: %Subscription{subscription_pid: subscription}} = state
      ) do
    Logger.debug(fn -> describe(state) <> " has successfully subscribed to event store" end)

    %Handler{handler_module: handler_module} = state

    case handler_module.init() do
      :ok ->
        {:noreply, state}

      {:stop, reason} ->
        Logger.debug(fn -> describe(state) <> " `init/0` callback has requested to stop" end)

        {:stop, reason, state}
    end
  end

  @doc false
  @impl GenServer
  def handle_info({:events, events}, %Handler{} = state) do
    %Handler{application: application} = state

    Logger.debug(fn -> describe(state) <> " received events: #{inspect(events)}" end)

    try do
      state =
        events
        |> Upcast.upcast_event_stream(additional_metadata: %{application: application})
        |> Enum.reduce(state, &handle_event/2)

      {:noreply, state}
    catch
      {:error, reason} ->
        # Stop after event handling returned an error
        {:stop, reason, state}
    end
  end

  @doc false
  @impl GenServer
  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %Handler{subscription: %Subscription{subscription_ref: ref}} = state
      ) do
    Logger.debug(fn -> describe(state) <> " subscription DOWN due to: #{inspect(reason)}" end)

    # Stop event handler when event store subscription process terminates.
    {:stop, reason, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:EXIT, _pid, :normal}, state) do
    # linked process exited normally, don't shutdown
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  @doc false
  @impl GenServer
  def handle_info(message, state) do
    Logger.error(fn ->
      describe(state) <> " received unexpected message: " <> inspect(message, pretty: true)
    end)

    {:noreply, state}
  end

  defp reset_subscription(%Handler{} = state) do
    %Handler{subscription: subscription} = state

    subscription = Subscription.reset(subscription)

    %Handler{state | last_seen_event: nil, subscription: subscription, subscribe_timer: nil}
  end

  defp subscribe_to_events(%Handler{} = state) do
    %Handler{subscription: subscription} = state

    case Subscription.subscribe(subscription, self()) do
      {:ok, subscription} ->
        %Handler{state | subscription: subscription, subscribe_timer: nil}

      {:error, error} ->
        {backoff, subscription} = Subscription.backoff(subscription)

        Logger.info(fn ->
          describe(state) <>
            " failed to subscribe to event store due to: " <>
            inspect(error) <> ", retrying in " <> inspect(backoff) <> "ms"
        end)

        subscribe_timer = Process.send_after(self(), :subscribe_to_events, backoff)

        %Handler{state | subscription: subscription, subscribe_timer: subscribe_timer}
    end
  end

  defp handle_event(event, context \\ %{}, handler)

  # Ignore already seen event.
  defp handle_event(
         %RecordedEvent{event_number: event_number} = event,
         _context,
         %Handler{last_seen_event: last_seen_event} = state
       )
       when not is_nil(last_seen_event) and event_number <= last_seen_event do
    Logger.debug(fn -> describe(state) <> " has already seen event ##{inspect(event_number)}" end)

    confirm_receipt(event, state)
  end

  # Delegate event to handler module.
  defp handle_event(%RecordedEvent{} = event, context, %Handler{} = state) do
    telemetry_metadata = telemetry_metadata(event, context, state)
    start_time = telemetry_start(telemetry_metadata)

    case delegate_event_to_handler(event, state) do
      :ok ->
        telemetry_stop(start_time, telemetry_metadata)

        confirm_receipt(event, state)

      {:ok, handler_state} ->
        telemetry_stop(start_time, Map.put(telemetry_metadata, :handler_state, handler_state))

        confirm_receipt(event, %Handler{state | handler_state: handler_state})

      {:error, :already_seen_event} ->
        telemetry_stop(start_time, Map.put(telemetry_metadata, :error, :already_seen_event))

        confirm_receipt(event, state)

      {:error, reason} = error ->
        log_event_error(error, event, state)
        telemetry_stop(start_time, Map.put(telemetry_metadata, :error, reason))

        failure_context = build_failure_context(event, context, state)

        handle_event_error(error, event, failure_context, state)

      {:error, reason, stacktrace} ->
        log_event_error({:error, reason}, event, state)
        telemetry_exception(start_time, :error, reason, stacktrace, telemetry_metadata)

        failure_context = build_failure_context(event, context, stacktrace, state)

        handle_event_error({:error, reason}, event, failure_context, state)

      invalid ->
        Logger.error(fn ->
          describe(state) <>
            " failed to handle event " <>
            inspect(event, pretty: true) <>
            ", `handle/2` function returned an invalid value: " <>
            inspect(invalid, pretty: true) <>
            ", expected `:ok` or `{:error, term}`"
        end)

        telemetry_stop(start_time, Map.put(telemetry_metadata, :error, :invalid_return_value))

        error = {:error, :invalid_return_value}
        failure_context = build_failure_context(event, context, state)

        handle_event_error(error, event, failure_context, state)
    end
  end

  defp delegate_event_to_handler(%RecordedEvent{} = event, %Handler{} = state) do
    %RecordedEvent{data: data} = event
    %Handler{handler_module: handler_module} = state

    metadata = enrich_metadata(event, state)

    try do
      handler_module.handle(data, metadata)
    rescue
      error ->
        stacktrace = __STACKTRACE__
        Logger.error(fn -> Exception.format(:error, error, stacktrace) end)

        {:error, error, stacktrace}
    end
  end

  defp build_failure_context(
         %RecordedEvent{} = failed_event,
         context,
         stacktrace \\ nil,
         %Handler{} = state
       ) do
    %Handler{application: application, handler_name: handler_name, handler_state: handler_state} =
      state

    metadata = enrich_metadata(failed_event, state)

    %FailureContext{
      application: application,
      handler_name: handler_name,
      handler_state: handler_state,
      context: context,
      metadata: metadata,
      stacktrace: stacktrace
    }
  end

  # Enrich the metadata with additional fields from the recorded event, plus the
  # associated Commanded application and the event handler's name.
  defp enrich_metadata(%RecordedEvent{} = event, %Handler{} = state) do
    %Handler{application: application, handler_name: handler_name, handler_state: handler_state} =
      state

    RecordedEvent.enrich_metadata(event,
      additional_metadata: %{
        application: application,
        handler_name: handler_name,
        state: handler_state
      }
    )
  end

  defp handle_event_error(
         error,
         %RecordedEvent{} = failed_event,
         %FailureContext{} = failure_context,
         %Handler{} = state
       ) do
    %RecordedEvent{data: data} = failed_event
    %Handler{handler_module: handler_module} = state

    case handler_module.error(error, data, failure_context) do
      {:retry, %FailureContext{context: context}} when is_map(context) ->
        # Retry the failed event
        Logger.info(fn -> describe(state) <> " is retrying failed event" end)

        handle_event(failed_event, context, state)

      {:retry, context} when is_map(context) ->
        # Retry the failed event
        Logger.info(fn -> describe(state) <> " is retrying failed event" end)

        handle_event(failed_event, context, state)

      {:retry, delay, %FailureContext{context: context}}
      when is_map(context) and is_integer(delay) and delay >= 0 ->
        # Retry the failed event after waiting for the given delay, in milliseconds
        Logger.info(fn ->
          describe(state) <> " is retrying failed event after #{inspect(delay)}ms"
        end)

        :timer.sleep(delay)

        handle_event(failed_event, context, state)

      {:retry, delay, context} when is_map(context) and is_integer(delay) and delay >= 0 ->
        # Retry the failed event after waiting for the given delay, in milliseconds
        Logger.info(fn ->
          describe(state) <> " is retrying failed event after #{inspect(delay)}ms"
        end)

        :timer.sleep(delay)

        handle_event(failed_event, context, state)

      :skip ->
        # Skip the failed event by confirming receipt
        Logger.info(fn -> describe(state) <> " is skipping event" end)

        confirm_receipt(failed_event, state)

      {:stop, reason} ->
        Logger.warn(fn -> describe(state) <> " has requested to stop: #{inspect(reason)}" end)

        # Stop event handler with given reason
        throw({:error, reason})

      invalid ->
        Logger.warn(fn ->
          describe(state) <> " returned an invalid error response: #{inspect(invalid)}"
        end)

        # Stop event handler with original error
        throw(error)
    end
  end

  defp log_event_error({:error, reason}, %RecordedEvent{} = failed_event, %Handler{} = state) do
    Logger.error(fn ->
      describe(state) <>
        " failed to handle event " <>
        inspect(failed_event, pretty: true) <>
        " due to: " <>
        inspect(reason, pretty: true)
    end)
  end

  # Confirm receipt of event
  defp confirm_receipt(%RecordedEvent{} = event, %Handler{} = state) do
    %Handler{
      application: application,
      consistency: consistency,
      handler_name: handler_name,
      subscription: subscription
    } = state

    %RecordedEvent{event_number: event_number} = event

    Logger.debug(fn ->
      describe(state) <> " confirming receipt of event ##{inspect(event_number)}"
    end)

    :ok = Subscription.ack_event(subscription, event)
    :ok = Subscriptions.ack_event(application, handler_name, consistency, event)

    %Handler{state | last_seen_event: event_number}
  end

  # Determine the partition key for an event to ensure ordered processing when
  # necessary.
  defp partition_event(
         %RecordedEvent{} = event,
         application,
         handler_name,
         handler_module
       ) do
    %RecordedEvent{data: data} =
      event = Upcast.upcast_event(event, additional_metadata: %{application: application})

    metadata =
      RecordedEvent.enrich_metadata(event,
        additional_metadata: %{
          application: application,
          handler_name: handler_name,
          state: nil
        }
      )

    try do
      handler_module.partition_by(data, metadata)
    rescue
      error ->
        stacktrace = __STACKTRACE__
        Logger.error(fn -> Exception.format(:error, error, stacktrace) end)

        1
    end
  end

  defp telemetry_start(telemetry_metadata) do
    Telemetry.start([:commanded, :event, :handle], telemetry_metadata)
  end

  defp telemetry_stop(start_time, telemetry_metadata) do
    Telemetry.stop([:commanded, :event, :handle], start_time, telemetry_metadata)
  end

  defp telemetry_exception(start_time, kind, reason, stacktrace, telemetry_metadata) do
    Telemetry.exception(
      [:commanded, :event, :handle],
      start_time,
      kind,
      reason,
      stacktrace,
      telemetry_metadata
    )
  end

  defp telemetry_metadata(recorded_event, context, %Handler{} = state) do
    %Handler{
      application: application,
      handler_name: handler_name,
      handler_module: handler_module,
      handler_state: handler_state
    } = state

    %{
      application: application,
      handler_name: handler_name,
      handler_module: handler_module,
      handler_state: handler_state,
      context: context,
      recorded_event: recorded_event
    }
  end

  defp consistency(opts) do
    case opts[:consistency] || Application.get_env(:commanded, :default_consistency, :eventual) do
      :eventual ->
        :eventual

      :strong ->
        if Keyword.get(opts, :concurrency, 1) > 1 do
          # Strong consistency is not supported for event handlers with concurrency
          raise ArgumentError, message: "cannot use `:strong` consistency with concurrency"
        else
          :strong
        end

      invalid ->
        raise ArgumentError, message: "invalid `consistency` option: #{inspect(invalid)}"
    end
  end

  defp new_subscription(application, handler_name, handler_module, handler_opts) do
    partition_by =
      if function_exported?(handler_module, :partition_by, 2) do
        fn event -> partition_event(event, application, handler_name, handler_module) end
      end

    Subscription.new(
      application: application,
      concurrency: Keyword.get(handler_opts, :concurrency, 1),
      partition_by: partition_by,
      subscription_name: handler_name,
      subscribe_from: Keyword.get(handler_opts, :start_from, :origin),
      subscribe_to: Keyword.get(handler_opts, :subscribe_to, :all),
      subscription_opts: Keyword.get(handler_opts, :subscription_opts, [])
    )
  end

  defp describe(%Handler{handler_module: handler_module}),
    do: inspect(handler_module)
end
