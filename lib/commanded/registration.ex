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

  @type start_child_arg :: {module(), keyword} | module()

  @doc """
  Return an optional supervisor spec for the registry
  """
  @callback child_spec(registry :: module) :: [:supervisor.child_spec()]

  @doc """
  Use to start a supervisor.
  """
  @callback supervisor_child_spec(registry :: module, module :: atom, arg :: any()) ::
              :supervisor.child_spec()

  @doc """
  Starts a uniquely named child process of a supervisor using the given module
  and args.

  Registers the pid with the given name.
  """
  @callback start_child(
              registry :: module,
              name :: term(),
              supervisor :: module(),
              child_spec :: start_child_arg
            ) ::
              {:ok, pid} | {:error, term}

  @doc """
  Starts a uniquely named `GenServer` process for the given module and args.

  Registers the pid with the given name.
  """
  @callback start_link(registry :: module, name :: term(), module :: module(), args :: any()) ::
              {:ok, pid} | {:error, term}

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @callback whereis_name(registry :: module, name :: term()) :: pid() | :undefined

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @callback via_tuple(registry :: module, name :: term()) :: {:via, module(), name :: term()}

  @doc """
  Get the configured process registry.

  Defaults to a local registry, restricted to running on a single node.
  """
  @spec registry_provider(application :: module, config :: Keyword.t()) :: module()
  def registry_provider(application, config) do
    registry = Keyword.get(config, :registry, :local)

    unless registry do
      raise ArgumentError, "missing :registry option on use Commanded.Application"
    end

    case registry do
      :local ->
        Commanded.Registration.LocalRegistry

      other when is_atom(other) ->
        other

      _invalid ->
        raise ArgumentError,
              "invalid :registry option for Commanded application " <> inspect(application)
    end
  end

  @doc """
  Use the `Commanded.Registration` module to import the registry provider and
  via tuple functions.
  """
  defmacro __using__(_opts) do
    quote location: :keep do
      @before_compile unquote(__MODULE__)

      alias unquote(__MODULE__)
    end
  end

  @doc """
  Allow a registry provider to handle the standard `GenServer` callback
  functions.
  """
  defmacro __before_compile__(_env) do
    quote generated: true, location: :keep do
      @doc false
      def handle_call(request, from, state) do
        registry_provider(state).handle_call(request, from, state)
      end

      @doc false
      def handle_cast(request, state) do
        registry_provider(state).handle_cast(request, state)
      end

      @doc false
      def handle_info(msg, state) do
        registry_provider(state).handle_info(msg, state)
      end

      defp registry_provider(state) do
        Keyword.get(state, :registry)
      end

      defp via_tuple(application, name) do
        registry = Module.concat([application, Registration])
        registry.via_tuple(name)
      end
    end
  end
end
