defmodule Commanded.Commands.IdentityAggregate do
  @moduledoc false
  defstruct [uuid: nil]

  defmodule IdentityCommand, do: defstruct [:uuid]
  defmodule IdentityEvent, do: defstruct [:uuid]

  def execute(%__MODULE__{}, %IdentityCommand{uuid: uuid}), do: %IdentityEvent{uuid: uuid}
  def apply(aggregate, _event), do: aggregate
end
