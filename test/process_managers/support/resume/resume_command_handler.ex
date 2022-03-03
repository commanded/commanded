defmodule Commanded.ProcessManagers.ResumeCommandHandler do
  @moduledoc false
  @behaviour Commanded.Commands.Handler

  alias Commanded.ProcessManagers.ResumeAggregate
  alias Commanded.ProcessManagers.ResumeAggregate.Commands.{ResumeProcess, StartProcess}

  def handle(%ResumeAggregate{} = aggregate, %StartProcess{} = start_process) do
    ResumeAggregate.start_process(aggregate, start_process)
  end

  def handle(%ResumeAggregate{} = aggregate, %ResumeProcess{} = resume_process) do
    ResumeAggregate.resume_process(aggregate, resume_process)
  end
end
