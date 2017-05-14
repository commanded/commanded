defmodule Commanded.Commands.Handler do
  @type aggregate :: struct()
  @type command :: struct()
  @type domain_events :: list(struct())
  @type reason :: term()

  @doc """
  Apply the given command to the event-sourced aggregate root.

  You must return a list containing the pending events, or `nil` / `[]` when no events produced.

  You should return `{:error, reason}` on failure.
  """
  @callback handle(aggregate, command) :: domain_events | nil | {:error, reason}
end
