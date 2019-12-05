defmodule Commanded.ProcessManagers.ProcessManager do
  @moduledoc """
  Macro used to define a process manager.

  A process manager is responsible for coordinating one or more aggregates.
  It handles events and dispatches commands in response. Process managers have
  state that can be used to track which aggregates are being orchestrated.

  Process managers can be used to implement long-running transactions by
  following the saga pattern. This is a sequence of commands and their
  compensating commands which can be used to rollback on failure.

  Use the `Commanded.ProcessManagers.ProcessManager` macro in your process
  manager module and implement the callback functions defined in the behaviour:

  - `c:interested?/1`
  - `c:handle/2`
  - `c:apply/2`
  - `c:error/3`

  Please read the [Process managers](process-managers.html) guide for more
  detail.

  ### Example

      defmodule ExampleProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          application: ExampleApp,
          name: "ExampleProcessManager"

        def interested?(%AnEvent{uuid: uuid}), do: {:start, uuid}

        def handle(%ExampleProcessManager{}, %ExampleEvent{}) do
          [
            %ExampleCommand{}
          ]
        end

        def error({:error, failure}, %ExampleEvent{}, _failure_context) do
          # Retry, skip, ignore, or stop process manager on error handling event
        end

        def error({:error, failure}, %ExampleCommand{}, _failure_context) do
          # Retry, skip, ignore, or stop process manager on error dispatching command
        end
      end

  Start the process manager (or configure as a worker inside a
  [Supervisor](supervision.html))

      {:ok, process_manager} = ExampleProcessManager.start_link()

  ## Error handling

  You can define an `c:error/3` callback function to handle any errors or
  exceptions during event handling or returned by commands dispatched from your
  process manager. The function is passed the error (e.g. `{:error, :failure}`),
  the failed event or command, and a failure context.
  See `Commanded.ProcessManagers.FailureContext` for details.

  Use pattern matching on the error and/or failed event/command to explicitly
  handle certain errors, events, or commands. You can choose to retry, skip,
  ignore, or stop the process manager after a command dispatch error.

  The default behaviour, if you don't provide an `c:error/3` callback, is to
  stop the process manager using the exact error reason returned from the
  event handler function or command dispatch. You should supervise your
  process managers to ensure they are restarted on error.

  ### Example

      defmodule ExampleProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          application: ExampleApp,
          name: "ExampleProcessManager"

        # stop process manager after three failures
        def error({:error, _failure}, _failed_command, %{context: %{failures: failures}})
          when failures >= 2
        do
          {:stop, :too_many_failures}
        end

        # retry command, record failure count in context map
        def error({:error, _failure}, _failed_command, %{context: context}) do
          context = Map.update(context, :failures, 1, fn failures -> failures + 1 end)

          {:retry, context}
        end
      end

  ## Idle process timeouts

  Each instance of a process manager will run indefinitely once started. To
  reduce memory usage you can configure an idle timeout, in milliseconds,
  after which the process will be shutdown.

  The process will be restarted whenever another event is routed to it and its
  state will be rehydrated from the instance snapshot.

  ### Example

      defmodule ExampleProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          application: ExampleApp,
          name: "ExampleProcessManager"
          idle_timeout: :timer.minutes(10)
      end

  ## Event handling timeout

  You can configure a timeout for event handling to ensure that events are
  processed in a timely manner without getting stuck.

  An `event_timeout` option, defined in milliseconds, may be provided when using
  the `Commanded.ProcessManagers.ProcessManager` macro at compile time:

      defmodule TransferMoneyProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          application: ExampleApp,
          name: "TransferMoneyProcessManager",
          router: BankRouter,
          event_timeout: :timer.minutes(10)
      end

  Or may be configured when starting a process manager:

      {:ok, _pid} = TransferMoneyProcessManager.start_link(
        event_timeout: :timer.hours(1)
      )

  After the timeout has elapsed, indicating the process manager has not
  processed an event within the configured period, the process manager is
  stopped. The process manager will be restarted if supervised and will retry
  the event, this should help resolve transient problems.

  ## Consistency

  For each process manager you can define its consistency, as one of either
  `:strong` or `:eventual`.

  This setting is used when dispatching commands and specifying the
  `consistency` option.

  When you dispatch a command using `:strong` consistency, after successful
  command dispatch the process will block until all process managers configured
  to use `:strong` consistency have processed the domain events created by the
  command.

  The default setting is `:eventual` consistency. Command dispatch will return
  immediately upon confirmation of event persistence, not waiting for any
  process managers.

  ### Example

  Define a process manager with `:strong` consistency:

      defmodule ExampleProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          application: ExampleApp,
          name: "ExampleProcessManager",
          consistency: :strong
      end

  ## Dynamic application

  A process manager's application can be provided as an option to `start_link/1`.
  This can be used to start the same handler multiple times, but using a
  separate Commanded application (and event store).

  ### Example

  Start a separate event handler process for each tenant, guaranteeing that the
  data and processing remains isolated between tenants.

      for tenant <- [:tenant1, :tenant2, :tenant3] do
        {:ok, _handler} = ExampleProcessManager.start_link(application: tenant)
      end

  Typically you would start the event handlers using a supervisor:

      handlers =
        for tenant <- [:tenant1, :tenant2, :tenant3] do
          {ExampleProcessManager, application: tenant}
        end

      Supervisor.start_link(handlers, strategy: :one_for_one)

  The above examples require three named Commanded applications to have already
  been started.
  """

  alias Commanded.ProcessManagers.FailureContext

  @type domain_event :: struct
  @type command :: struct
  @type process_manager :: struct
  @type process_uuid :: String.t() | [String.t()]
  @type consistency :: :eventual | :strong

  @doc """
  Is the process manager interested in the given command?

  The `c:interested?/1` function is used to indicate which events the process
  manager receives. The response is used to route the event to an existing
  instance or start a new process instance:

  - `{:start, process_uuid}` - create a new instance of the process manager.
  - `{:start!, process_uuid}` - create a new instance of the process manager (strict).
  - `{:continue, process_uuid}` - continue execution of an existing process manager.
  - `{:continue!, process_uuid}` - continue execution of an existing process manager (strict).
  - `{:stop, process_uuid}` - stop an existing process manager, shutdown its
    process, and delete its persisted state.
  - `false` - ignore the event.

  You can return a list of process identifiers when a single domain event is to
  be handled by multiple process instances.

  ## Strict process routing

  Using strict routing, with `:start!` or `:continue`, enforces the following
  validation checks:

  - `{:start!, process_uuid}` - validate process does not already exist.
  - `{:continue!, process_uuid}` - validate process already exists.

  If the check fails an error will be passed to the `error/3` callback function:

  - `{:error, {:start!, :process_already_started}}`
  - `{:error, {:continue!, :process_not_started}}`

  The `error/3` function can choose to `:stop` the process or `:skip` the
  problematic event.

  """
  @callback interested?(domain_event) ::
              {:start, process_uuid}
              | {:start!, process_uuid}
              | {:continue, process_uuid}
              | {:continue!, process_uuid}
              | {:stop, process_uuid}
              | false

  @doc """
  Process manager instance handles a domain event, returning any commands to
  dispatch.

  A `c:handle/2` function can be defined for each `:start` and `:continue`
  tagged event previously specified. It receives the process manager's state and
  the event to be handled. It must return the commands to be dispatched. This
  may be none, a single command, or many commands.

  The `c:handle/2` function can be omitted if you do not need to dispatch a
  command and are only mutating the process manager's state.
  """
  @callback handle(process_manager, domain_event) :: command | list(command) | {:error, term}

  @doc """
  Mutate the process manager's state by applying the domain event.

  The `c:apply/2` function is used to mutate the process manager's state. It
  receives the current state and the domain event, and must return the modified
  state.

  This callback function is optional, the default behaviour is to retain the
  process manager's current state.
  """
  @callback apply(process_manager, domain_event) :: process_manager

  @doc """
  Called when a command dispatch or event handling returns an error.

  The `c:error/3` function allows you to control how command dispatch and event
  handling failures are handled. The function is passed the error (e.g.
  `{:error, :failure}`), the failed command (during failed dispatch) or failed
  event (during failed event handling), and a failure context struct (see
  `Commanded.ProcessManagers.FailureContext` for details).

  The failure context contains a context map you can use to pass transient state
  between failures. For example it can be used to count the number of failures.

  You can return one of the following responses depending upon the
  error severity:

  - `{:retry, context}` - retry the failed command, provide a context
    map containing any state passed to subsequent failures. This could be used
    to count the number of retries, failing after too many attempts.

  - `{:retry, delay, context}` - retry the failed command, after sleeping for
    the requested delay (in milliseconds). Context is a map as described in
    `{:retry, context}` above.

  - `{:skip, :discard_pending}` - discard the failed command and any pending
    commands.

  - `{:skip, :continue_pending}` - skip the failed command, but continue
    dispatching any pending commands.

  - `{:continue, commands, context}` - continue dispatching the given commands.
    This allows you to retry the failed command, modify it and retry, drop it,
    or drop all pending commands by passing an empty list `[]`. Context is a map
    as described in `{:retry, context}` above.

  - `{:stop, reason}` - stop the process manager with the given reason.

  """
  @callback error(
              error :: {:error, term()},
              failure_source :: command | domain_event,
              failure_context :: FailureContext.t()
            ) ::
              {:retry, context :: map()}
              | {:retry, delay :: non_neg_integer(), context :: map()}
              | {:skip, :discard_pending}
              | {:skip, :continue_pending}
              | {:continue, commands :: list(command), context :: map()}
              | {:stop, reason :: term()}

  alias Commanded.Event.Handler
  alias Commanded.ProcessManagers.ProcessManager
  alias Commanded.ProcessManagers.ProcessRouter

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)

      @behaviour ProcessManager

      {application, name} = ProcessManager.compile_config(__MODULE__, unquote(opts))

      @opts unquote(opts)
      @application application
      @name name

      def start_link(opts \\ []) do
        application = Keyword.get(opts, :application, @application)
        module_opts = Keyword.drop(@opts, [:application, :name])
        opts = Handler.start_opts(__MODULE__, module_opts, opts, [:event_timeout, :idle_timeout])

        ProcessRouter.start_link(application, @name, __MODULE__, opts)
      end

      @doc """
      Provides a child specification to allow the event handler to be easily
      supervised.

      ## Example

          Supervisor.start_link([
            {ExampleProcessManager, []}
          ], strategy: :one_for_one)

      """
      def child_spec(opts) do
        application = Keyword.get(opts, :application, @application)

        default = %{
          id: {__MODULE__, application, @name},
          start: {__MODULE__, :start_link, [opts]},
          restart: :permanent,
          type: :worker
        }

        Supervisor.child_spec(default, [])
      end

      @doc false
      def __name__, do: @name
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    # include default fallback functions at end, with lowest precedence
    quote generated: true do
      @doc false
      def interested?(_event), do: false

      @doc false
      def handle(_process_manager, _event), do: []

      @doc false
      def apply(process_manager, _event), do: process_manager

      @doc false
      def error({:error, reason}, _command, _failure_context), do: {:stop, reason}
    end
  end

  def compile_config(module, opts) do
    application = Keyword.get(opts, :application)

    unless application do
      raise ArgumentError, inspect(module) <> " expects :application option"
    end

    name = Handler.parse_name(module, Keyword.get(opts, :name))

    {application, name}
  end
end
