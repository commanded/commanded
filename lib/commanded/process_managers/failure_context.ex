defmodule Commanded.ProcessManagers.FailureContext do
  @moduledoc """
  Data related to a process manager event handling or command dispatch failure.

  The available fields are:

    - `context` - the context map passed between each failure and may be used
      to track state between retries, such as to count failures.

    - `enriched_metadata` - the enriched metadata associated with the event.

    - `last_event` - the last event the process manager received.

    - `pending_commands` - the pending commands that were not executed yet.

    - `process_manager_state` - the state the process manager would be in
      if the event handling or command dispatch had not failed.

    - `stacktrace` - the stacktrace if the error was an unhandled exception.

  """
  alias Commanded.EventStore.RecordedEvent

  @type t :: %__MODULE__{
          context: map(),
          enriched_metadata: map(),
          last_event: RecordedEvent.t(),
          pending_commands: [struct()],
          process_manager_state: struct(),
          stacktrace: Exception.stacktrace() | nil
        }

  defstruct [
    :enriched_metadata,
    :last_event,
    :process_manager_state,
    :stacktrace,
    context: %{},
    pending_commands: []
  ]
end
