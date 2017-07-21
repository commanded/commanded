defmodule Commanded.ProcessManagers.ProcessManager do
  @moduledoc """
  Behaviour to define a process manager
  """

  @type domain_event :: struct
  @type command :: struct
  @type process_manager :: struct
  @type process_uuid :: String.t

  @doc """
  Is the process manager interested in the given command?
  """
  @callback interested?(domain_event) :: {:start, process_uuid} | {:continue, process_uuid} | {:stop, process_uuid} | false

  @doc """
  Process manager instance handles the domain event, returning commands to dispatch
  """
  @callback handle(process_manager, domain_event) :: list(command)

  @doc """
  Mutate the process manager's state by applying the domain event
  """
  @callback apply(process_manager, domain_event) :: process_manager

  @doc """
  Macro as a convenience for defining a process manager

    defmodule ExampleProcessManager do
      use Commanded.ProcessManagers.ProcessManager,
        name: "example_process_manager",
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

    # start process manager (or configure as a worker inside a supervisor)
    {:ok, process_manager} = ExampleProcessManager.start_link()
  """
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
          |> Keyword.take([:start_from])
          |> Keyword.merge(opts)

        Commanded.ProcessManagers.ProcessRouter.start_link(@name, __MODULE__, @router, opts)
      end
    end
  end

  # include default fallback functions at end, with lowest precedence
  defmacro __before_compile__(_env) do
    quote do
      def interested?(_event), do: false
      def handle(_process_manager, _event), do: []
      def apply(process_manager, _event), do: process_manager
    end
  end
end
