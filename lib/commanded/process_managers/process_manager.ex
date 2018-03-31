defmodule Commanded.ProcessManagers.ProcessManager do
  @moduledoc """
  Behaviour to define a process manager.

  A process manager is responsible for coordinating one or more aggregates.
  It handles events and dispatches commands in response. Process managers have
  state that can be used to track which aggregates are being orchestrated.

  Use the `Commanded.ProcessManagers.ProcessManager` macro in your process
  manager module and implement the callback functions defined in the behaviour:

  - `c:interested?/1`
  - `c:handle/2`
  - `c:apply/2`
  - `c:error/3`

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

        def error({:error, failure}, %ExampleCommand{}, _failure_context) do
          # retry, skip, ignore, or stop process manager on error dispatching command
        end
      end

  Start the process manager (or configure as a worker inside a [Supervisor](supervision.html))

      {:ok, process_manager} = ExampleProcessManager.start_link()

  # Error handling

  You can define an `c:error/3` callback function to handle any errors returned
  by commands dispatched from your process manager. The function is passed the
  command dispatch error (e.g. `{:error, :failure}`), the failed command, and a
  failure context. See `Commanded.ProcessManagers.FailureContext` for details.

  Use pattern matching on the error and/or failed command to explicitly handle
  certain errors or commands. You can choose to retry, skip, ignore, or stop the
  process manager after a command dispatch error.

  The default behaviour, if you don't provide an `c:error/3` callback, is to
  stop the process manager using the exact error reason returned from the
  command dispatch. You should supervise your process managers to ensure they
  are restarted on error.

  ## Example

      defmodule ExampleProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          name: "ExampleProcessManager",
          router: ExampleRouter

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
  - `{:continue, process_uuid}` - continue execution of an existing process manager.
  - `{:stop, process_uuid}` - stop an existing process manager, shutdown its
    process, and delete its persisted state.
  - `false` - ignore the event.

  You can return a list of process identifiers when a single domain event must
  be handled by multiple process instances.
  """
  @callback interested?(domain_event) :: {:start, process_uuid}
    | {:continue, process_uuid}
    | {:stop, process_uuid} | false

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
  @callback handle(process_manager, domain_event) :: list(command)

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
  Called when a command dispatch returns an error.

  The `c:error/3` function allows you to control how command dispatch failures
  are handled. The function is passed the command dispatch error (e.g. `{:error,
  :failure}`), the failed command, and a failure context struct
  (see `Commanded.ProcessManagers.FailureContext` for details). This contains a
  context map you can use to pass transient state between failures. For example
  it can be used to count the number of failures.

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
  @callback error(error :: term(), failed_command :: command, failure_context :: FailureContext.t()) :: {:retry, context :: map()}
    | {:retry, delay :: non_neg_integer(), context :: map()}
    | {:skip, :discard_pending}
    | {:skip, :continue_pending}
    | {:continue, commands :: list(command), context :: map()}
    | {:stop, reason :: term()}

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)
      @on_definition {unquote(__MODULE__), :emit_deprecated_warnings}

      @behaviour Commanded.ProcessManagers.ProcessManager

      @opts unquote(opts) || []
      @name Commanded.Event.Handler.parse_name(__MODULE__, @opts[:name])
      @router @opts[:router] || raise "#{inspect __MODULE__} expects `:router` to be given"

      def start_link(opts \\ []) do
        opts = Commanded.Event.Handler.start_opts(__MODULE__, Keyword.drop(@opts, [:name, :router]), opts)

        Commanded.ProcessManagers.ProcessRouter.start_link(@name, __MODULE__, @router, opts)
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
        default = %{
          id: {__MODULE__, @name},
          start: {__MODULE__, :start_link, [opts]},
          restart: :permanent,
          type: :worker,
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
    quote do
      @doc false
      def interested?(_event), do: false

      @doc false
      def handle(_process_manager, _event), do: []

      @doc false
      def apply(process_manager, _event), do: process_manager

      @doc false
      def error({:error, reason}, failed, %{pending_commands: pending, context: context}) do
        error({:error, reason}, failed, pending, context)
      end

      @doc false
      def error({:error, reason}, _failed_command, _pending_commands, _context),
        do: {:stop, reason}
    end
  end

  def emit_deprecated_warnings(env, _kind, name, args, _guards, _body) do
    arity = length(args)
    mod = env.module

    case {name, arity} do
      {:error, 4} ->
        if Module.defines?(mod, {name, arity}) do
          mod
          |> error_deprecation_message
          |> IO.warn()
        end

      _ ->
        nil
    end
  end

  defp error_deprecation_message(mod) do
    """
    Commanded Deprecation Warning:

    Process manager #{mod} defined `error/4` callback, this has been deprecated in favor of `error/3`.

    See https://github.com/commanded/commanded/blob/master/guides/Process%20Managers.md#deprecated-error4
    """
  end
end
