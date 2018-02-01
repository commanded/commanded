defmodule Commanded.Event.ErrorRouter do
  @moduledoc false

  use Commanded.Commands.Router

  alias Commanded.Event.ErrorAggregate
  alias Commanded.Event.ErrorAggregate.Commands.RaiseError

  dispatch [RaiseError], to: ErrorAggregate, identity: :uuid
end
