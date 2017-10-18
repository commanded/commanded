defmodule Commanded.Commands.ExecutionResult do
  @moduledoc """
  Contains the events and metadata created by a command succesfully executed
  against an aggregate.

  The available fields are:

  - `aggregate_uuid` - identity of the aggregate instance.
  - `aggregate_version` - resultant version of the aggregate after executing
    the command.
  - `events` - a list of the created events, may be an empty list.
  - `metadata` - an optional map containing the metadata associated with the
    command dispatch.

  """

  @type t :: %__MODULE__{
    aggregate_uuid: String.t,
    aggregate_version: non_neg_integer(),
    events: list(struct()),
    metadata: struct(),
  }

  defstruct [
    aggregate_uuid: nil,
    aggregate_version: nil,
    events: nil,
    metadata: nil,
  ]
end
