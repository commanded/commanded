defmodule Commanded.ProcessManagers.ErrorRouter do
  @moduledoc false
  use Commanded.Commands.Router

  alias Commanded.ProcessManagers.ErrorAggregate
  alias Commanded.ProcessManagers.ErrorAggregate.Commands.{
    StartProcess,
    AttemptProcess,
    ContinueProcess,
  }

  dispatch [StartProcess,AttemptProcess,ContinueProcess],
    to: ErrorAggregate, identity: :process_uuid
end
