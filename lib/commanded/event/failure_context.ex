defmodule Commanded.Event.FailureContext do
  @moduledoc """
  Data related to an event handling failure.

  The available fields are:

    - `:application` - the associated `Commanded.Application`.

    - `:handler_name` - the name of the event handler.

    - `:handler_state` - optional event handler state.

    - `:context` - a map that is passed between each failure. Use it to store
      any transient state between failures. As an example it could be used to
      count error failures and stop or skip the problematic event after too
      many.

    - `:metadata` - the metadata associated with the failed event.

    - `:stacktrace` - the stacktrace if the error was an unhandled exception.

  """

  @type t :: %__MODULE__{
          application: Commanded.Application.t(),
          handler_name: String.t(),
          handler_state: nil | any(),
          context: map(),
          metadata: map(),
          stacktrace: Exception.stacktrace() | nil
        }

  defstruct [
    :application,
    :handler_name,
    :handler_state,
    :context,
    :metadata,
    :stacktrace
  ]
end
