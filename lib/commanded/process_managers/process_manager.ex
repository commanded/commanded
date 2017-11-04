defmodule Commanded.ProcessManagers.ProcessManager do
  @moduledoc """
  Behaviour to define a process manager.

  A process manager is responsible for coordinating one or more aggregate roots.
  It handles events and dispatches commands in response. Process managers have
  state that can be used to track which aggregate roots are being orchestrated.

  Use the `Commanded.ProcessManagers.ProcessManager` macro in your process
  manager module and implement the callback functions defined in the behaviour:

  - `c:interested?/1`
  - `c:handle/2`
  - `c:apply/2`
  - `c:error/4`

  ## Example

      defmodule ExampleProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          name: "ExampleProcessManager",
          router: ExampleRouter

        def interested?(%AnEvent{...}) do
          # ...
        end

        def handle(%ExampleProcessManager{...}, %AnEvent{...}) do
          # ...
        end

        def apply(%ExampleProcessManager{...}, %AnEvent{...}) do
          # ...
        end

        def error({:error, failure}, %ExampleCommand{}, _pending_commands, %{} = context) do
          # retry, skip, ignore, or stop process manager on error dispatching command
        end
      end

  Start the process manager (or configure as a worker inside a [Supervisor](supervision.html))

      {:ok, process_manager} = ExampleProcessManager.start_link()

  # Error handling

  You can define an `c:error/4` callback function to handle any errors returned
  from command dispatch. The function is passed the command dispatch error (e.g.
  `{:error, :failure}`), the failed command, any pending commands, and a context
  map containing state passed between retries.

  Use pattern matching on the error and/or failed command to explicitly handle
  certain errors or commands. You can choose to retry, skip, ignore, or stop the
  process manager after an error dispatching command.

  The default behaviour if you don't provide an `c:error/4` callback is to stop
  the process manager using the exact error reason returned from the command
  dispatch. You should supervise process managers to ensure they are correctly
  restarted on error.

  ## Example

      defmodule ExampleProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          name: "ExampleProcessManager",
          router: ExampleRouter

        # stop process manager after three attempts
        def error({:error, _failure}, _failed_command, _pending_commands, %{attempts: attempts} = context)
          when attempts >= 2
        do
          {:stop, :too_many_attempts}
        end

        # retry command, record attempt count in context map
        def error({:error, _failure}, _failed_command, _pending_commands, context) do
          context = Map.update(context, :attempts, 1, fn attempts -> attempts + 1 end)
          {:retry, context}
        end
      end

  # Consistency

  For each process manager you can define its consistency, as one of either
  `:strong` or `:eventual`.

  This setting is used when dispatching commands and specifying the `consistency`
  option.

  When you dispatch a command using `:strong` consistency, after successful
  command dispatch the process will block until all process managers configured to
  use `:strong` consistency have processed the domain events created by the
  command.

  The default setting is `:eventual` consistency. Command dispatch will return
  immediately upon confirmation of event persistence, not waiting for any
  process managers.

  ## Example

      defmodule ExampleProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          name: "ExampleProcessManager",
          router: BankRouter
          consistency: :strong

        # ...
      end

  Please read the [Process managers](process-managers.html) guide for more details.
  """

  @type domain_event :: struct
  @type command :: struct
  @type process_manager :: struct
  @type process_uuid :: String.t
  @type consistency :: :eventual | :strong

  @doc """
  Is the process manager interested in the given command?

  The `c:interested?/1` function is used to indicate which events the process
  manager receives. The response is used to route the event to an existing
  instance or start a new process instance:

  - `{:start, process_uuid}` - create a new instance of the process manager.
  - `{:continue, process_uuid}` - continue execution of an existing process manager.
  - `{:stop, process_uuid}` - stop an existing process manager and shutdown its process.
  - `false` - ignore the event.
  """
  @callback interested?(domain_event) :: {:start, process_uuid} | {:continue, process_uuid} | {:stop, process_uuid} | false

  @doc """
  Process manager instance handles the domain event, returning commands to dispatch.

  A `c:handle/2` function must exist for each `:start` and `:continue` tagged
  event previously specified. It receives the process manager’s state and the
  event to be handled. It must return the commands to be dispatched. This may be
  none, a single command, or many commands.
  """
  @callback handle(process_manager, domain_event) :: list(command)

  @doc """
  Mutate the process manager's state by applying the domain event.

  The `c:apply/2` function is used to mutate the process manager’s state. It
  receives its current state and the interested event. It must return the
  modified state.
  """
  @callback apply(process_manager, domain_event) :: process_manager

  @doc """
  Called when a command dispatch returns an error.

  The `c:error/4` function allows you to control how command dispatch failures
  are handled. The function is passed the command dispatch error (e.g. `{:error,
  :failure}`), the failed command, any pending commands, and a context map
  containing state passed between retries. The context may also be used to track
  state between retried failures.

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
  @callback error(error :: term(), failed_command :: command, pending_commands :: list(command), context :: map()) :: {:retry, context :: map()}
    | {:retry, delay :: non_neg_integer(), context :: map()}
    | {:skip, :discard_pending}
    | {:skip, :continue_pending}
    | {:continue, commands :: list(command), context :: map()}
    | {:stop, reason :: term()}

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)

      @behaviour Commanded.ProcessManagers.ProcessManager

      @opts unquote(opts) || []
      @name Commanded.Event.Handler.parse_name(__MODULE__, @opts[:name])
      @router @opts[:router] || raise "#{inspect __MODULE__} expects `:router` to be given"

      def start_link(opts \\ []) do
        opts =
          @opts
          |> Keyword.take([:consistency, :start_from])
          |> Keyword.merge(opts)

        Commanded.ProcessManagers.ProcessRouter.start_link(@name, __MODULE__, @router, opts)
      end
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    # include default fallback functions at end, with lowest precedence
    quote do
      @doc false
      def interested?(_event), do: false

      @doc false
      def handle(_process_manager, _event), do: []

      @doc false
      def apply(process_manager, _event), do: process_manager

      @doc false
      def error({:error, reason}, _failed_command, _pending_commands, _context),
        do: {:stop, reason}
    end
  end
end
