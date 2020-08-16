defmodule Commanded.ProcessManagers.FailureContext do
  @moduledoc """
  Data related to a process manager event handling or command dispatch failure.

  The available fields are:

    - `context` - the context map passed between each failure and may be used
      to track state between retries, such as to count failures.

    - `last_event` - the last event the process manager received.

    - `pending_commands` - the pending commands that were not executed yet.

    - `process_manager_state` - the state the process manager would be in
      if the command would not fail.

    - `stacktrace` - the stacktrace if the error was an unhandled exception.

  """

  @type t :: %__MODULE__{
          context: map(),
          last_event: struct(),
          pending_commands: [struct()],
          process_manager_state: struct(),
          stacktrace: Exception.stacktrace() | nil
        }

  defstruct [
    :process_manager_state,
    :last_event,
    :stacktrace,
    context: %{},
    pending_commands: []
  ]
end
