defmodule Commanded.ProcessManagers.ExampleRouter do
  @moduledoc false
  use Commanded.Commands.Router

  alias Commanded.ProcessManagers.{ExampleAggregate, ExampleCommandHandler}
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.{Error, Publish, Raise, Start, Stop}

  dispatch [Error, Publish, Raise, Start, Stop],
    to: ExampleCommandHandler,
    aggregate: ExampleAggregate,
    identity: :aggregate_uuid
end
