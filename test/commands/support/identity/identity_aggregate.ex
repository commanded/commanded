defmodule Commanded.Commands.IdentityAggregate do
  @moduledoc false
  @derive Jason.Encoder
  defstruct uuid: nil

  defmodule IdentityCommand do
    @derive Jason.Encoder
    defstruct([:uuid])
  end

  defmodule IdentityEvent do
    @derive Jason.Encoder
    defstruct([:uuid])
  end

  def execute(%__MODULE__{}, %IdentityCommand{uuid: uuid}), do: %IdentityEvent{uuid: uuid}
  def apply(aggregate, _event), do: aggregate
end
