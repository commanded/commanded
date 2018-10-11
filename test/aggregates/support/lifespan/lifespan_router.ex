defmodule Commanded.Aggregates.LifespanRouter do
  use Commanded.Commands.Router

  alias Commanded.Aggregates.Lifespan
  alias Commanded.Aggregates.LifespanAggregate
  alias Commanded.Aggregates.LifespanAggregate.Command

  dispatch [Command], to: LifespanAggregate, identity: :uuid, lifespan: Lifespan
end
