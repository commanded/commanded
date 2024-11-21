defmodule Commanded.Event.ErrorHandler.Stop do
  alias Commanded.Event.ErrorHandler

  @behaviour ErrorHandler

  @impl ErrorHandler
  def handle_error({:error, reason}, _event, _failure_context) do
    {:stop, reason}
  end
end
