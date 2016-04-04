defmodule Commanded.Commands.Handler do
  @doc """
  Define which entity the command applies to
  """
  @callback entity() :: atom

  @doc """
  Apply the given command to the event sourced entity state, returning state struct containing the entity's id, all applied events and current version
  """
  @callback handle(state :: EventSourced.Entity, command :: %{}) :: EventSourced.Entity
end
