defmodule Commanded.Commands.ConsistencyAggregateRoot do
  @moduledoc false
  @derive Jason.Encoder
  defstruct [:delay]

  defmodule ConsistencyCommand do
    @derive Jason.Encoder
    defstruct [:uuid, :delay]
  end

  defmodule NoOpCommand do
    @derive Jason.Encoder
    defstruct [:uuid]
  end

  defmodule RequestDispatchCommand do
    @derive Jason.Encoder
    defstruct [:uuid, :delay]
  end

  defmodule ConsistencyEvent do
    @derive Jason.Encoder
    defstruct [:uuid, :delay]
  end

  defmodule DispatchRequestedEvent do
    @derive Jason.Encoder
    defstruct [:uuid, :delay]
  end

  alias Commanded.Commands.ConsistencyAggregateRoot

  def execute(%ConsistencyAggregateRoot{}, %ConsistencyCommand{uuid: uuid, delay: delay}) do
    %ConsistencyEvent{uuid: uuid, delay: delay}
  end

  def execute(%ConsistencyAggregateRoot{}, %NoOpCommand{}), do: []

  def execute(%ConsistencyAggregateRoot{}, %RequestDispatchCommand{uuid: uuid, delay: delay}) do
    %DispatchRequestedEvent{uuid: uuid, delay: delay}
  end

  def apply(%ConsistencyAggregateRoot{} = aggregate, %ConsistencyEvent{delay: delay}) do
    %ConsistencyAggregateRoot{aggregate | delay: delay}
  end

  def apply(%ConsistencyAggregateRoot{} = aggregate, _event), do: aggregate
end
