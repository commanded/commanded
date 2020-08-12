defmodule Commanded.Registration.GlobalRegistry do
  @moduledoc """
  Distributed process registration using Erlangs `:global` registry[1].

  [1] http://erlang.org/doc/man/global.html
  """

  @behaviour Commanded.Registration.Adapter

  @doc """
  Return an optional supervisor spec for the registry
  """
  @impl Commanded.Registration.Adapter
  def child_spec(application, _config) do
    {:ok, [], %{application: application}}
  end

  @doc """
  Starts a supervisor.
  """
  @impl Commanded.Registration.Adapter
  def supervisor_child_spec(_adapter_meta, module, arg) do
    spec = %{
      id: module,
      start: {module, :start_link, [arg]},
      type: :supervisor
    }

    Supervisor.child_spec(spec, [])
  end

  @doc """
  Starts a uniquely named child process of a supervisor using the given module
  and args.

  Registers the pid with the given name.
  """
  @impl Commanded.Registration.Adapter
  def start_child(adapter_meta, name, supervisor, child_spec) do
    via_name = via_tuple(adapter_meta, name)

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
  @impl Commanded.Registration.Adapter
  def start_link(adapter_meta, name, module, args, start_opts) do
    via_name = via_tuple(adapter_meta, name)
    start_opts = Keyword.put(start_opts, :name, via_name)

    case GenServer.start_link(module, args, start_opts) do
      {:error, {:already_started, pid}} ->
        true = Process.link(pid)

        {:ok, pid}

      {:error, :killed} ->
        # Process may be killed due to `:global` name registation when another node connects.
        # Attempting to start again should link to the other named existing process.
        start_link(adapter_meta, name, module, args, start_opts)

      reply ->
        reply
    end
  end

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @impl Commanded.Registration.Adapter
  def whereis_name(adapter_meta, name) do
    global_name = global_name(adapter_meta, name)

    :global.whereis_name(global_name)
  end

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @impl Commanded.Registration.Adapter
  def via_tuple(adapter_meta, name) do
    global_name = global_name(adapter_meta, name)

    {:via, :global, global_name}
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

  defp global_name(adapter_meta, name) do
    application = Map.fetch!(adapter_meta, :application)

    {application, name}
  end
end
