defmodule Commanded.Commands.IdentityFunctionAggregate do
  @moduledoc false
  defstruct [uuid: nil]

  defmodule IdentityFunctionCommand, do: defstruct [:uuid]
  defmodule IdentityFunctionEvent, do: defstruct [:uuid]

  def execute(%__MODULE__{}, %IdentityFunctionCommand{uuid: uuid}), do: %IdentityFunctionEvent{uuid: uuid}
  def apply(aggregate, _event), do: aggregate
end
