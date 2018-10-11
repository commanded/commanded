defmodule Commanded.Aggregates.DefaultLifespanRouter do
  use Commanded.Commands.Router

  alias Commanded.Aggregates.LifespanAggregate
  alias Commanded.Aggregates.LifespanAggregate.Command

  dispatch [Command], to: LifespanAggregate, identity: :uuid
end
