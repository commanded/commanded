defmodule Commanded.Commands.ExampleRouter do
  use Commanded.Commands.Router

  alias Commanded.Commands.ExampleCommand
  alias Commanded.Commands.ExampleAggregate

  dispatch ExampleCommand, to: ExampleAggregate, identity: :id
end
