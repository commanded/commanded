defmodule Commanded.Commands.UnregisteredCommand do
  @moduledoc false
  alias Uniq.UUID

  defstruct aggregate_uuid: UUID.uuid4()
end
