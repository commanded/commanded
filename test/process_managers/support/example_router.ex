defmodule Commanded.ProcessManagers.ExampleRouter do
  @moduledoc false

  use Commanded.Commands.Router

  alias Commanded.ProcessManagers.{ExampleAggregate, ExampleCommandHandler}

  alias Commanded.ProcessManagers.ExampleAggregate.Commands.{
    Continue,
    Error,
    Pause,
    Publish,
    Raise,
    Start,
    Stop
  }

  dispatch [Error, Pause, Publish, Raise, Start, Stop, Continue],
    to: ExampleCommandHandler,
    aggregate: ExampleAggregate,
    identity: :aggregate_uuid
end
