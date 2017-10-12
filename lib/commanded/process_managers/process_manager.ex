defmodule Commanded.ProcessManagers.ProcessManager do
  @moduledoc """
  Behaviour to define a process manager.

  A process manager is responsible for coordinating one or more aggregate roots.
  It handles events and dispatches commands in response. Process managers have
  state that can be used to track which aggregate roots are being orchestrated.

  Use the `Commanded.ProcessManagers.ProcessManager` macro in your process
  manager module and implement the three callback functions defined in the
  behaviour:

  - `c:interested?/1`
  - `c:handle/2`
  - `c:apply/2`

  ## Example

      defmodule ExampleProcessManager do
        use Commanded.ProcessManagers.ProcessManager,
          name: "ExampleProcessManager",
          router: BankRouter

        def interested?(%AnEvent{...}) do
          # ...
        end

        def handle(%ExampleProcessManager{...}, %AnEvent{...}) do
          # ...
        end

        def apply(%ExampleProcessManager{...}, %AnEvent{...}) do
          # ...
        end
      end

  Start the process manager (or configure as a worker inside a [Supervisor](supervision.html))

      {:ok, process_manager} = ExampleProcessManager.start_link()

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
  Called when a command dispatch returns an error.

  The `c:error/3` function allows you to control how command dispatch failures
  are handled. The function receives the error returned from the dispatch, the
  domain event being handled, and a context map containing the dispatched
  command. The context may also be used to track state between retried failures.

  You can return one of the following responses depending upon the
  error severity:

  - {:retry, context} - retry the event, provide a context map to provide state
    to subsequent failures. This could be used to count the number of retries,
    failing after too many attempts.
  - {:retry, delay, context} - retry the event, after sleeping for the requested
    delay, given in milliseconds. Context is as per the above retry.
  - :skip - discard the event, don't dispatch any pending commands.
  - :ignore - ignore the error and continue dispatching any remaining commands.
  - {:stop, reason} - stop the process manager with the given reason.
  """
  @callback error(error :: term(), command, context :: map()) :: {:retry, context :: map()}
    | {:retry, delay :: non_neg_integer(), context :: map()}
    | :skip
    | :ignore
    | {:stop, reason :: term()}

  @doc """
  Mutate the process manager's state by applying the domain event.

  The `c:apply/2` function is used to mutate the process manager’s state. It
  receives its current state and the interested event. It must return the
  modified state.
  """
  @callback apply(process_manager, domain_event) :: process_manager

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)

      @behaviour Commanded.ProcessManagers.ProcessManager

      @opts unquote(opts) || []
      @name @opts[:name] || raise "#{inspect __MODULE__} expects :name to be given"
      @router @opts[:router] || raise "#{inspect __MODULE__} expects :router to be given"

      def start_link(opts \\ []) do
        opts =
          @opts
          |> Keyword.take([:consistency, :start_from])
          |> Keyword.merge(opts)

        Commanded.ProcessManagers.ProcessRouter.start_link(@name, __MODULE__, @router, opts)
      end
    end
  end

  # include default fallback functions at end, with lowest precedence
  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc false
      def interested?(_event), do: false

      @doc false
      def handle(_process_manager, _event), do: []

      @doc false
      def apply(process_manager, _event), do: process_manager
    end
  end
end
