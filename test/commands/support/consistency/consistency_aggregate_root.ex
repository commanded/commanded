defmodule Commanded.Commands.ConsistencyAggregateRoot do
  @moduledoc false
  defstruct [:delay]

  defmodule ConsistencyCommand, do: defstruct [:uuid, :delay]
  defmodule NoOpCommand, do: defstruct [:uuid]
  defmodule RequestDispatchCommand, do: defstruct [:uuid, :delay]
  defmodule ConsistencyEvent, do: defstruct [:uuid, :delay]
  defmodule DispatchRequestedEvent, do: defstruct [:uuid, :delay]

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
