defmodule Commanded.Registration do
  @moduledoc """
  Defines a behaviour for a process registry to be used by Commanded.

  By default, Commanded will use a local process registry, defined in
  `Commanded.Registration.LocalRegistry`, that uses Elixir's `Registry` module
  for local process registration. This limits Commanded to only run on a single
  node. However the `Commanded.Registration` behaviour can be implemented by a
  library to provide distributed process registration to support running on a
  cluster of nodes.
  """

  @doc """
  Return an optional supervisor spec for the registry
  """
  @callback child_spec() :: [:supervisor.child_spec()]

  @doc """
  Starts a uniquely named child process of a supervisor using the given module
  and args.

  Registers the pid with the given name.
  """
  @callback start_child(name :: term(), supervisor :: module(), args :: [any()]) ::
              {:ok, pid} | {:error, term}

  @doc """
  Starts a uniquely named `GenServer` process for the given module and args.

  Registers the pid with the given name.
  """
  @callback start_link(name :: term(), module :: module(), args :: any()) ::
              {:ok, pid} | {:error, term}

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @callback whereis_name(name :: term()) :: pid() | :undefined

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @callback via_tuple(name :: term()) :: {:via, module(), name :: term()}

  @doc false
  @spec child_spec() :: [:supervisor.child_spec()]
  def child_spec, do: registry_provider().child_spec()

  @doc false
  @callback start_child(name :: term(), supervisor :: module(), args :: [any()]) ::
              {:ok, pid()} | {:error, reason :: term()}
  def start_child(name, supervisor, args),
    do: registry_provider().start_child(name, supervisor, args)

  @doc false
  @spec start_link(name :: term(), module :: module(), args :: any()) ::
          {:ok, pid()} | {:error, reason :: term()}
  def start_link(name, module, args), do: registry_provider().start_link(name, module, args)

  @doc false
  @spec whereis_name(term()) :: pid() | :undefined
  def whereis_name(name), do: registry_provider().whereis_name(name)

  @doc false
  @spec via_tuple(name :: term()) :: {:via, module(), name :: term()}
  def via_tuple(name), do: registry_provider().via_tuple(name)

  @doc """
  Get the configured process registry.

  Defaults to a local registry, restricted to running on a single node, if not configured.
  """
  @spec registry_provider() :: module()
  def registry_provider do
    case Application.get_env(:commanded, :registry, :local) do
      :local -> Commanded.Registration.LocalRegistry
      other -> other
    end
  end

  @doc """
  Use the `Commanded.Registration` module to import the registry provider and via tuple functions.
  """
  defmacro __using__(_) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)

      import unquote(__MODULE__), only: [registry_provider: 0, via_tuple: 1]
      alias unquote(__MODULE__)
    end
  end

  @doc """
  Allow a registry provider to handle the standard `GenServer` callback functions
  """
  defmacro __before_compile__(_env) do
    quote location: :keep do
      @doc false
      def handle_call(request, from, state),
        do: registry_provider().handle_call(request, from, state)

      @doc false
      def handle_cast(request, state),
        do: registry_provider().handle_cast(request, state)

      @doc false
      def handle_info(msg, state),
        do: registry_provider().handle_info(msg, state)
    end
  end
end
