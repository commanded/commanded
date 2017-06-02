alias Commanded.Aggregates.DistributedAggregate
defprotocol Commanded.Aggregates.DistributedAggregate do
  @moduledoc """
  This protocol is implemented by aggregate modules to define recovery behaviour in distributed systems

  The process registry, Swarm, handles network topology changes and netsplits. In most cases,
  the default is sufficient; restart the node on the new machine, loading state from the eventstore.
  """
  @fallback_to_any true

  @doc """
  Handles handoff of aggregate state from another process in the event of a cluster topology change.

  Returns {:restart} by default, which will restart the process on a new node. Other valid values are:
  - {:resume, state] to hand off state to the new process
  - {:ignore} will leave the current process running
  """
  def begin_handoff(state)

  @doc """
  Is called after a process has been restarted on a new node and is accepting the previous processes state.

  Only called in the event that begin_handoff returns {:resume, state}

  Returns the new state of the process
  """
  def end_handoff(current_state, handoff_state)

  @doc """
  Called in the event of a network partition (netsplit). Use to recover and merge divergent states.

  Returns new state of the aggregate.
  """
  def resolve_conflict(current_state, conflicting_state)

  @doc """
  Handle cleanup of aggregate process, called when Swarm is moving the process to a new node.

  Returns {:stop, :shutdown, state} by default.
  """
  def cleanup(state)
end

defimpl DistributedAggregate, for: Any do
  def begin_handoff(_state) do
    {:restart}
  end

  def end_handoff(_current_state, _handoff_state) do
    raise "Implement Commanded.Aggregates.DistributedAggregate protocol to handle Swarm process handoff"
  end

  def resolve_conflict(current_state, _conflicting_state) do
    current_state
  end

  def cleanup(state) do
    {:stop, :shutdown, state}
  end
end
