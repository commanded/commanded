defmodule Commanded.Aggregates.ExampleAggregate do
  @moduledoc false
  @derive Jason.Encoder
  defstruct items: [],
            last_index: 0

  defmodule Commands do
    defmodule AppendItems do
      defstruct count: 0
    end

    defmodule NoOp do
      defstruct count: 0
    end
  end

  defmodule Events do
    defmodule ItemAppended do
      @derive Jason.Encoder
      defstruct [:index]
    end
  end

  alias Commanded.Aggregates.ExampleAggregate
  alias Commands.NoOp
  alias Events.ItemAppended

  def append_items(%ExampleAggregate{last_index: last_index}, count) do
    Enum.map(1..count, fn index ->
      %ItemAppended{index: last_index + index}
    end)
  end

  def noop(%ExampleAggregate{}, %NoOp{}), do: []

  # State mutators

  def apply(%ExampleAggregate{items: items} = state, %ItemAppended{index: index}) do
    %ExampleAggregate{state | items: items ++ [index], last_index: index}
  end
end
