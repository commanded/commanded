defmodule Commanded.Commands.Handler do
  @doc """
  Apply the given command to the event sourced entity state, returning state struct containing the entity's id, all applied events and current version
  """
  @callback handle(state :: EventSourced.Entity, command :: %{}) :: EventSourced.Entity
end
