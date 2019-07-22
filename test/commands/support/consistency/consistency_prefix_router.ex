defmodule Commanded.Commands.ConsistencyPrefixRouter do
  use Commanded.Commands.Router

  alias Commanded.Commands.ConsistencyAggregateRoot

  alias ConsistencyAggregateRoot.{
    ConsistencyCommand,
    NoOpCommand,
    RequestDispatchCommand
  }

  identify ConsistencyAggregateRoot,
    by: :uuid,
    prefix: "example-prefix-"

  dispatch [ConsistencyCommand, NoOpCommand, RequestDispatchCommand],
    to: ConsistencyAggregateRoot
end
