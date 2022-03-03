defmodule Commanded.ProcessManagers.ResumeRouter do
  @moduledoc false

  use Commanded.Commands.Router

  alias Commanded.ProcessManagers.{ResumeAggregate, ResumeCommandHandler}
  alias Commanded.ProcessManagers.ResumeAggregate.Commands.{ResumeProcess, StartProcess}

  dispatch StartProcess,
    to: ResumeCommandHandler,
    aggregate: ResumeAggregate,
    identity: :process_uuid

  dispatch ResumeProcess,
    to: ResumeCommandHandler,
    aggregate: ResumeAggregate,
    identity: :process_uuid
end
