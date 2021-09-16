defmodule Commanded.Commands.UnregisteredCommand do
  @moduledoc false
  alias Commanded.UUID

  defstruct aggregate_uuid: UUID.uuid4()
end
