defmodule Commanded.Commands.ExecutionResult do
  @moduledoc """
  Contains the aggregate, events, and metadata created by a successfully
  executed command.

  The available fields are:

    - `aggregate_uuid` - identity of the aggregate instance.

    - `aggregate_state` - resultant state of the aggregate after executing
      the command.

    - `aggregate_version` - resultant version of the aggregate after executing
      the command.

    - `events` - a list of the created events, it may be an empty list.

    - `metadata` - an map containing the metadata associated with the command
      dispatch.

  """

  @type t :: %__MODULE__{
          aggregate_uuid: String.t(),
          aggregate_state: struct,
          aggregate_version: non_neg_integer(),
          events: list(struct()),
          metadata: struct()
        }

  @enforce_keys [:aggregate_uuid, :aggregate_state, :aggregate_version, :events, :metadata]

  defstruct [
    :aggregate_uuid,
    :aggregate_state,
    :aggregate_version,
    :events,
    :metadata
  ]
end
