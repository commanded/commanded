defmodule Commanded.ProcessManagers.ResumeAggregate do
  @moduledoc false
  defstruct [status: nil]

  defmodule Commands do
    defmodule StartProcess, do: defstruct [process_uuid: nil, status: nil]
    defmodule ResumeProcess, do: defstruct [process_uuid: nil, status: nil]
  end

  defmodule Events do
    defmodule ProcessStarted, do: defstruct [process_uuid: nil, status: nil]
    defmodule ProcessResumed, do: defstruct [process_uuid: nil, status: nil]
  end

  alias Commanded.ProcessManagers.ResumeAggregate
  alias Commanded.ProcessManagers.ResumeAggregate.Commands.{StartProcess,ResumeProcess}
  alias Commanded.ProcessManagers.ResumeAggregate.Events.{ProcessStarted,ProcessResumed}

  def start_process(%ResumeAggregate{}, %StartProcess{process_uuid: process_uuid, status: status}) do
    %ProcessStarted{process_uuid: process_uuid, status: status}
  end

  def resume_process(%ResumeAggregate{}, %ResumeProcess{process_uuid: process_uuid, status: status}) do
    %ProcessResumed{process_uuid: process_uuid, status: status}
  end

  # state mutatators

  def apply(%ResumeAggregate{} = state, %ProcessStarted{status: status}), do: %ResumeAggregate{state | status: status}
  def apply(%ResumeAggregate{} = state, %ProcessResumed{status: status}), do: %ResumeAggregate{state | status: status}
end
