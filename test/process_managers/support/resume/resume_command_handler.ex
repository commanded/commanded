defmodule Commanded.ProcessManagers.ResumeCommandHandler do
  @moduledoc false
  @behaviour Commanded.Commands.Handler

  alias Commanded.ProcessManagers.ResumeAggregate
  alias Commanded.ProcessManagers.ResumeAggregate.Commands.{StartProcess,ResumeProcess}

  def handle(%ResumeAggregate{} = aggregate, %StartProcess{} = start_process) do
    aggregate
    |> ResumeAggregate.start_process(start_process)
  end

  def handle(%ResumeAggregate{} = aggregate, %ResumeProcess{} = resume_process) do
    aggregate
    |> ResumeAggregate.resume_process(resume_process)
  end
end
