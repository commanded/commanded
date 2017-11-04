defmodule Commanded.ProcessManagers.ResumeProcessManager do
  @moduledoc false
  use Commanded.ProcessManagers.ProcessManager,
    name: "resume-process-manager",
    router: ResumeRouter

  defstruct [
    status_history: []
  ]

  alias Commanded.ProcessManagers.ResumeAggregate.Events.{ProcessStarted,ProcessResumed}
  alias Commanded.ProcessManagers.ResumeProcessManager

  def interested?(%ProcessStarted{process_uuid: process_uuid}), do: {:start, process_uuid}
  def interested?(%ProcessResumed{process_uuid: process_uuid}), do: {:continue, process_uuid}

  def handle(%ResumeProcessManager{}, %ProcessStarted{}), do: []
  def handle(%ResumeProcessManager{}, %ProcessResumed{}), do: []

  ## state mutators

  def apply(%ResumeProcessManager{status_history: status_history} = process, %ProcessStarted{status: status}) do
    %ResumeProcessManager{process |
      status_history: status_history ++ [status]
    }
  end

  def apply(%ResumeProcessManager{status_history: status_history} = process, %ProcessResumed{status: status}) do
    %ResumeProcessManager{process |
      status_history: status_history ++ [status]
    }
  end
end
