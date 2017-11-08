defmodule Commanded.Commands.IdentityAggregateRouter do
  @moduledoc false
  use Commanded.Commands.Router

  alias Commanded.Commands.IdentityAggregate
  alias Commanded.Commands.IdentityAggregate.IdentityCommand

  identify IdentityAggregate,
    by: :uuid,
    prefix: "prefix-"

  dispatch IdentityCommand, to: IdentityAggregate
end
