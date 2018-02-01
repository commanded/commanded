defmodule Commanded.Event.FailureContext do
  @moduledoc """
  Contains the data related to an event handling failure.

  The available fields are:

  - `context` - a map that is passed between each failure. Use it to store any
    transient state between failures. As an example it could be used to count
    error failures and stop or skip the problematic event after too many.
  - `metadata` - the metadata associated with the failed event.

  """

  @type t :: %__MODULE__{
          context: map(),
          metadata: map()
        }

  defstruct [
    :context,
    :metadata
  ]
end
