defmodule Commanded.ProcessManagers.ErrorRouter do
  @moduledoc false

  use Commanded.Commands.Router

  alias Commanded.ProcessManagers.ErrorAggregate

  alias Commanded.ProcessManagers.ErrorAggregate.Commands.{
    AttemptProcess,
    ContinueProcess,
    RaiseError,
    RaiseException,
    StartProcess
  }

  dispatch [AttemptProcess, ContinueProcess, RaiseError, RaiseException, StartProcess],
    to: ErrorAggregate,
    identity: :process_uuid
end
