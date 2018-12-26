defmodule Commanded.Commands.IdentityFunctionAggregate do
  @moduledoc false
  @derive Jason.Encoder
  defstruct uuid: nil

  defmodule IdentityFunctionCommand do
    @derive Jason.Encoder
    defstruct [:uuid]
  end

  defmodule IdentityFunctionEvent do
    @derive Jason.Encoder
    defstruct [:uuid]
  end

  def execute(%__MODULE__{}, %IdentityFunctionCommand{uuid: uuid}),
    do: %IdentityFunctionEvent{uuid: uuid}

  def apply(aggregate, _event), do: aggregate
end
