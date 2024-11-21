defmodule Commanded.Event.ErrorHandler.GrumpyOldBastard do
  def handle_error(_error, _event, _failure_context) do
    {:stop, "You have no business coding on the BEAM."}
  end
end
