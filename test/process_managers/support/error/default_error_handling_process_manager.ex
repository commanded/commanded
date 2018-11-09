defmodule Commanded.ProcessManagers.DefaultErrorHandlingProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.{DefaultErrorHandlingProcessManager, ErrorRouter}
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.AttemptProcess
  alias Commanded.ProcessManagers.ErrorAggregate.Events.ProcessStarted

  use Commanded.ProcessManagers.ProcessManager,
    name: "DefaultErrorHandlingProcessManager",
    router: ErrorRouter

  defstruct [:process_uuid]

  def interested?(%ProcessStarted{process_uuid: process_uuid}), do: {:start, process_uuid}

  def handle(%DefaultErrorHandlingProcessManager{}, %ProcessStarted{process_uuid: process_uuid}) do
    %AttemptProcess{process_uuid: process_uuid}
  end
end
