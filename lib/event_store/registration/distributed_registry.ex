defmodule EventStore.Registration.DistributedRegistry do
  @moduledoc """
  Process registration and distribution throughout a cluster of nodes using [Swarm](https://github.com/bitwalker/swarm)
  """

  @behaviour EventStore.Registration

  @doc """
  Return an optional supervisor spec for the registry
  """
  @spec child_spec() :: [:supervisor.child_spec()]
  @impl EventStore.Registration
  def child_spec, do: []

  @doc """
  Starts a uniquely named child process of a supervisor using the given module and args.

  Registers the pid with the given name.
  """
  @spec start_child(name :: term(), supervisor :: module(), args :: [any()]) :: {:ok, pid()} | {:error, reason :: term()}
  @impl EventStore.Registration
  def start_child(name, supervisor, args) do
    case whereis_name(name) do
      :undefined ->
        case Swarm.register_name(name, Supervisor, :start_child, [supervisor, args]) do
          {:error, {:already_registered, pid}} -> {:error, {:already_started, pid}}
          reply -> reply
        end

      pid ->
        {:ok, pid}
    end
  end

  @doc """
  Get the pid of a registered name.
  """
  @spec whereis_name(name :: term) :: pid | :undefined
  @impl EventStore.Registration
  def whereis_name(name), do: Swarm.whereis_name(name)

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @spec via_tuple(name :: term()) :: {:via, module(), name :: term()}
  @impl EventStore.Registration
  def via_tuple(name), do: {:via, :swarm, name}

  @doc """
  Publish events to the `EventStore.Publisher` running on each connected node
  """
  @callback publish_events(stream_uuid :: term, events :: list(EventStore.RecordedEvent.t)) :: :ok
  @impl EventStore.Registration
  def publish_events(stream_uuid, events) do
    # send to publisher on current node and all connected nodes
    [Node.self() | Node.list(:connected)]
    |> Enum.map(&Task.async(fn -> publish_events_to_node(&1, stream_uuid, events) end))
    |> Enum.map(&Task.await(&1, 30_000))
  end

  #
  # `GenServer` callback functions used by Swarm
  #

  # Shutdown the process when a cluster toplogy change indicates it is now running on the wrong host.
  # This is to prevent a spike in process restarts as they are moved. Instead, allow the process to
  # be started on request.
  def handle_call({:swarm, :begin_handoff}, _from, state) do
    {:stop, :shutdown, :ignore, state}
  end

  def handle_cast({:swarm, :end_handoff, _state}, state) do
    {:noreply, state}
  end

  # Take the remote process state after net split has been resolved
  def handle_cast({:swarm, :resolve_conflict, state}, _state) do
    {:noreply, state}
  end

  # Stop the process as it is being moved to another node, or there are not currently enough nodes running
  def handle_info({:swarm, :die}, state) do
    {:stop, :shutdown, state}
  end

  defp publish_events_to_node(node, stream_uuid, events) do
    send({EventStore.Publisher, node}, {:notify_events, stream_uuid, events})
  end
end
