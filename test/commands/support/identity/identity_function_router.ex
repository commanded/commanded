defmodule Commanded.Commands.IdentityFunctionRouter do
  @moduledoc false
  use Commanded.Commands.Router

  alias Commanded.Commands.{IdentityFunctionAggregate, IdentityFunctionRouter}
  alias Commanded.Commands.IdentityFunctionAggregate.IdentityFunctionCommand

  identify IdentityFunctionAggregate,
    by: &IdentityFunctionRouter.aggregate_identity/1

  dispatch IdentityFunctionCommand, to: IdentityFunctionAggregate

  def aggregate_identity(%{uuid: uuid}), do: "identityfun-" <> uuid
end
