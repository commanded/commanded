defmodule Commanded.Commands.ExampleRouter do
  use Commanded.Commands.Router

  alias Commanded.Commands.{ExampleAggregate, ExampleCommand}

  dispatch ExampleCommand, to: ExampleAggregate, identity: :id
end
