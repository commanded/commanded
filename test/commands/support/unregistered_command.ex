defmodule Commanded.Commands.UnregisteredCommand do
  @moduledoc false
  defstruct [aggregate_uuid: UUID.uuid4]
end
