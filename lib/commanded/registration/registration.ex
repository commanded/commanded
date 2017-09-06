defmodule Commanded.Registration do
  @moduledoc """
  Process registry specification
  """

  @doc """
  Return an optional supervisor spec for the registry
  """
  @callback child_spec() :: [:supervisor.child_spec()]

  @doc """
  Starts a uniquely named `GenServer` process for the given module and args.

  Registers the pid with the given name.
  """
  @callback start_link(name :: term(), module :: module(), args :: [any()]) :: {:ok, pid()} | {:error, reason :: term()}

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
  @spec start_link(name :: term(), module :: module(), args :: [any()]) :: {:ok, pid()} | {:error, reason :: term()}
  def start_link(name, module, args), do: registry_provider().start_link(name, module, args)

  @doc false
  @spec whereis_name(term()) :: pid() | :undefined
  def whereis_name(name), do: registry_provider().whereis_name(name)

  @doc false
  @spec via_tuple(name :: term()) :: {:via, module(), name :: term()}
  def via_tuple(name), do: registry_provider().via_tuple(name)

  @doc """
  Get the configured process registry
  """
  @spec registry_provider() :: module()
  def registry_provider do
    case Application.get_env(:commanded, :registry) do
      nil -> raise ArgumentError, "Commanded expects `:registry` to be configured in environment"
      :local -> Commanded.Registration.LocalRegistry
      other -> other
    end
  end

  @doc """
  Use the `Commanded.Registration` module to import the registry and via tuple functions.
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
      def handle_call(request, from, state), do: registry_provider().handle_call(request, from, state)

      @doc false
      def handle_cast(request, state), do: registry_provider().handle_cast(request, state)

      @doc false
      def handle_info(msg, state), do: registry_provider().handle_info(msg, state)
    end
  end
end
