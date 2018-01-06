defmodule Commanded.ProcessManagers.FailureContext do
  @moduledoc """
  Contains the data related to a failure.

  The available fields are:

  - `pending_commands` - the pending commands that were not executed yet
  - `process_manager_state` - the state the process manager would be in
    if the command would not fail.
  - `last_event` - the last event the process manager received
  - `context` - the context of failures (to be passed between each failure),
    used in example to count retries.
  """

  @type t :: %__MODULE__{
    pending_commands: [struct()],
    process_manager_state: struct(),
    last_event: struct(),
    context: map()
  }

  defstruct [
    pending_commands: nil,
    process_manager_state: nil,
    last_event: nil,
    context: nil
  ]
end
