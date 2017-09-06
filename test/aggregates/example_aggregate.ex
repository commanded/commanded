defmodule Commanded.Aggregates.ExampleAggregate do
  defstruct [
    items: [],
    last_index: 0,
  ]

  defmodule Commands do
    defmodule AppendItems, do: defstruct [count: 0]
    defmodule NoOp, do: defstruct [count: 0]
  end

  defmodule Events do
    defmodule ItemAppended, do: defstruct [:index]
  end

  alias Commanded.Aggregates.ExampleAggregate
  alias Commands.{AppendItems,NoOp}
  alias Events.ItemAppended

  def append_items(%ExampleAggregate{last_index: last_index}, count) do
    Enum.map(1..count, fn index ->
      %ItemAppended{index: last_index + index}
    end)
  end

  def noop(%ExampleAggregate{}, %NoOp{}), do: []

  # state mutatators

  def apply(%ExampleAggregate{items: items} = state, %ItemAppended{index: index}) do
    %ExampleAggregate{state |
      items: items ++ [index],
      last_index: index,
    }
  end
end
