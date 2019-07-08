defmodule Commanded.Registration.LocalRegistry do
  @moduledoc """
  Local process registration, restricted to a single node, using Elixir's
  [Registry](https://hexdocs.pm/elixir/Registry.html).
  """

  @behaviour Commanded.Registration

  @doc """
  Return an optional supervisor spec for the registry
  """
  @impl Commanded.Registration
  def child_spec(registry) do
    registry_name = registry_name(registry)

    [
      {Registry, keys: :unique, name: registry_name}
    ]
  end

  @doc """
  Starts a supervisor.
  """
  @impl Commanded.Registration
  def supervisor_child_spec(_registry, module, arg) do
    default = %{
      id: module,
      start: {module, :start_link, [arg]},
      type: :supervisor
    }

    Supervisor.child_spec(default, [])
  end

  @doc """
  Starts a uniquely named child process of a supervisor using the given module
  and args.

  Registers the pid with the given name.
  """

  @impl Commanded.Registration
  def start_child(registry, name, supervisor, child_spec) do
    via_name = via_tuple(registry, name)

    child_spec =
      case child_spec do
        module when is_atom(module) ->
          {module, name: via_name}

        {module, args} when is_atom(module) and is_list(args) ->
          {module, Keyword.put(args, :name, via_name)}
      end

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      reply -> reply
    end
  end

  @doc """
  Starts a uniquely named `GenServer` process for the given module and args.

  Registers the pid with the given name.
  """
  @impl Commanded.Registration
  def start_link(registry, name, module, args) do
    via_name = via_tuple(registry, name)

    case GenServer.start_link(module, args, name: via_name) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      reply -> reply
    end
  end

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @impl Commanded.Registration
  def whereis_name(registry, name) do
    registry_name = registry_name(registry)
    Registry.whereis_name({registry_name, name})
  end

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @impl Commanded.Registration
  def via_tuple(registry, name) do
    registry_name = registry_name(registry)
    {:via, Registry, {registry_name, name}}
  end

  @doc false
  def handle_call(_request, _from, _state) do
    raise "attempted to call GenServer #{inspect(proc())} but no handle_call/3 clause was provided"
  end

  @doc false
  def handle_cast(_request, _state) do
    raise "attempted to cast GenServer #{inspect(proc())} but no handle_cast/2 clause was provided"
  end

  @doc false
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp proc do
    case Process.info(self(), :registered_name) do
      {_, []} -> self()
      {_, name} -> name
    end
  end

  defp registry_name(registry), do: Module.concat([registry, LocalRegistry])
end
