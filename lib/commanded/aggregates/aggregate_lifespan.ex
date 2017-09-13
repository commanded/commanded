defmodule Commanded.Aggregates.AggregateLifespan do
  @moduledoc """
  The `Commanded.Aggregates.AggregateLifespan` behaviour is used to control an aggregate lifespan.

  By default an aggregate instance process will run indefinitely once started.
  You can control this by implementing the `Commanded.Aggregates.AggregateLifespan` behaviour in a module.

  The `c:after_command/1` function is called after each command executes.
  The returned timeout value is used to shutdown the aggregate process if no other messages are recevied.

  Return `:infinity` to prevent the aggregate instance from shutting down.
  """

  @type command :: struct()
  @type timeout_or_action :: timeout() | :infinity | :hibernate

  @doc """
  After specified timeout aggregate process will be stoped.

  Timeout begins at start of processing a command.
  """
  @callback after_command(command) :: timeout_or_action
end
