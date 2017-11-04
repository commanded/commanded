defmodule Commanded.Commands.AggregateRouter do
  @moduledoc false
  use Commanded.Commands.Router

  alias Commanded.Commands.AggregateRoot
  alias Commanded.Commands.AggregateRoot.Command

  dispatch Command, to: AggregateRoot, identity: :uuid
end
