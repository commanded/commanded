defmodule Commanded.Commands.Handler do
  @doc """
  Apply the given command to the event-sourced aggregate root.

  You must return the updated aggregate root on success. This is the struct containing the aggregate's id, pending events and current version.

  You should return `{:error, reason}` on failure.
  """
  @callback handle(EventSourced.AggregateRoot, command :: %{}) :: EventSourced.AggregateRoot | {:error, reason :: term}
end
