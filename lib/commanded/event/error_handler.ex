defmodule Commanded.Event.ErrorHandler do
  alias Commanded.Event.FailureContext

  @type failure_context :: map() | %FailureContext{context: map}
  @type reason :: term()
  @type delay :: non_neg_integer()

  @callback handle_error({:error, reason}, struct(), %FailureContext{context: map}) ::
              :skip
              | {:retry, failure_context}
              | {:retry, delay, failure_context}
              | {:stop, reason}
end
