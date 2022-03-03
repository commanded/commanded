defmodule Commanded.ProcessManagers.ResumeAggregate do
  @moduledoc false

  defstruct [:status]

  defmodule Commands do
    defmodule(StartProcess, do: defstruct([:process_uuid, :status]))
    defmodule(ResumeProcess, do: defstruct([:process_uuid, :status]))
  end

  defmodule Events do
    defmodule ProcessStarted do
      @derive Jason.Encoder
      defstruct([:process_uuid, :status])
    end

    defmodule ProcessResumed do
      @derive Jason.Encoder
      defstruct([:process_uuid, :status])
    end
  end

  alias Commanded.ProcessManagers.ResumeAggregate
  alias Commanded.ProcessManagers.ResumeAggregate.Commands.{ResumeProcess, StartProcess}
  alias Commanded.ProcessManagers.ResumeAggregate.Events.{ProcessResumed, ProcessStarted}

  def start_process(%ResumeAggregate{}, %StartProcess{process_uuid: process_uuid, status: status}) do
    %ProcessStarted{process_uuid: process_uuid, status: status}
  end

  def resume_process(%ResumeAggregate{}, %ResumeProcess{} = command) do
    %ResumeProcess{process_uuid: process_uuid, status: status} = command

    %ProcessResumed{process_uuid: process_uuid, status: status}
  end

  # State mutators

  def apply(%ResumeAggregate{} = state, %ProcessStarted{status: status}),
    do: %ResumeAggregate{state | status: status}

  def apply(%ResumeAggregate{} = state, %ProcessResumed{status: status}),
    do: %ResumeAggregate{state | status: status}
end
