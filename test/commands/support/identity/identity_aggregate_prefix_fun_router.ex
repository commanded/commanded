defmodule Commanded.Commands.IdentityAggregatePrefixFunRouter do
  @moduledoc false
  use Commanded.Commands.Router

  alias Commanded.Commands.IdentityAggregatePrefixFunRouter
  alias Commanded.Commands.IdentityAggregate
  alias Commanded.Commands.IdentityAggregate.IdentityCommand

  identify IdentityAggregate,
    by: :uuid,
    prefix: &IdentityAggregatePrefixFunRouter.prefix/0

  dispatch IdentityCommand, to: IdentityAggregate

  def prefix do
    "funprefix-"
  end
end
