defmodule Commanded.Commands.AggregateRouter do
  @moduledoc false
  use Commanded.Commands.Router

  alias Commanded.Commands.AggregateRoot
  alias Commanded.Commands.AggregateRoot.{Command, Command2}

  dispatch Command, to: AggregateRoot, identity: :uuid
  dispatch Command2, to: AggregateRoot, function: :custom_function_name, identity: :uuid
end
