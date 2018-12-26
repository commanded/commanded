defmodule Commanded.Aggregates.LifespanAggregate do
  @moduledoc false
  @derive Jason.Encoder
  defstruct [:uuid, :reply_to, :lifespan]

  defmodule Command do
    @derive Jason.Encoder
    defstruct [:uuid, :reply_to, :action, :lifespan]
  end

  defmodule Event do
    @derive Jason.Encoder
    defstruct [:uuid, :reply_to, :lifespan]
  end

  alias Commanded.Aggregates.LifespanAggregate

  def execute(%LifespanAggregate{}, %Command{action: :event} = command) do
    %Command{uuid: uuid, reply_to: reply_to, lifespan: lifespan} = command

    %Event{uuid: uuid, reply_to: reply_to, lifespan: lifespan}
  end

  def execute(%LifespanAggregate{}, %Command{action: :noop}) do
    []
  end

  def execute(%LifespanAggregate{}, %Command{action: :error} = command) do
    %Command{reply_to: reply_to, lifespan: lifespan} = command

    {:error, {:failed, reply_to, lifespan}}
  end

  # State mutators

  def apply(%LifespanAggregate{} = state, %Event{} = event) do
    %Event{uuid: uuid, reply_to: reply_to, lifespan: lifespan} = event

    %LifespanAggregate{state | uuid: uuid, reply_to: reply_to, lifespan: lifespan}
  end
end
