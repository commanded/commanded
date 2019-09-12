defmodule Commanded.Commands.ConsistencyRouter do
  use Commanded.Commands.Router

  alias Commanded.Commands.ConsistencyAggregateRoot
  alias ConsistencyAggregateRoot.ConsistencyCommand
  alias ConsistencyAggregateRoot.NoOpCommand
  alias ConsistencyAggregateRoot.RequestDispatchCommand

  dispatch [ConsistencyCommand, NoOpCommand, RequestDispatchCommand],
    to: ConsistencyAggregateRoot,
    identity: :uuid
end
