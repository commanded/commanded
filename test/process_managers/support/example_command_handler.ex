defmodule Commanded.ProcessManagers.ExampleCommandHandler do
  @moduledoc false
  @behaviour Commanded.Commands.Handler

  alias Commanded.ProcessManagers.ExampleAggregate
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.{
    Error,
    Publish,
    Start,
    Stop,
  }

  def handle(%ExampleAggregate{} = aggregate, %Start{aggregate_uuid: aggregate_uuid}),
    do: ExampleAggregate.start(aggregate, aggregate_uuid)

  def handle(%ExampleAggregate{} = aggregate, %Publish{interesting: interesting, uninteresting: uninteresting}),
    do: ExampleAggregate.publish(aggregate, interesting, uninteresting)

  def handle(%ExampleAggregate{} = aggregate, %Stop{}),
    do: ExampleAggregate.stop(aggregate)

  def handle(%ExampleAggregate{} = aggregate, %Error{}),
    do: ExampleAggregate.error(aggregate)
end
