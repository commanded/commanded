defmodule Commanded.Aggregates.AppendItemsHandler do
  @behaviour Commanded.Commands.Handler

  alias Commanded.Aggregates.ExampleAggregate
  alias Commanded.Aggregates.ExampleAggregate.Commands.AppendItems

  def handle(%ExampleAggregate{} = aggregate, %AppendItems{count: count}) do
    ExampleAggregate.append_items(aggregate, count)
  end
end
