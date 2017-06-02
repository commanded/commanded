defmodule Commanded.Aggregates.AggregateLifespan do
  @type command :: struct()
  @type timeout_or_action :: timeout() | :hibernate

  @doc """
  After specified timeout aggregate process will be stoped.

  Timeout begins at start of processing a command.
  """
  @callback after_command(command) :: timeout_or_action
end
