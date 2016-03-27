defmodule Commanded.CommandHandler do
  @doc """
  Define which aggregate applies for this command
  """
  @callback aggregate() :: atom

  @doc """
  Handle the given command, returning state struct containing the aggregate's uuid, all applied events and expected version
  """
  @callback handle(state :: EventSourced.Entity, command :: %{}) :: EventSourced.Entity
end
