defmodule Commanded.ProcessManagers.ExampleCommandHandler do
  @moduledoc false
  @behaviour Commanded.Commands.Handler

  alias Commanded.ProcessManagers.ExampleAggregate

  alias Commanded.ProcessManagers.ExampleAggregate.Commands.{
    Error,
    Pause,
    Publish,
    Raise,
    Start,
    Stop,
    Continue
  }

  def handle(%ExampleAggregate{} = aggregate, %Start{aggregate_uuid: aggregate_uuid}),
    do: ExampleAggregate.start(aggregate, aggregate_uuid)

  def handle(%ExampleAggregate{} = aggregate, %Publish{} = command) do
    %Publish{interesting: interesting, uninteresting: uninteresting} = command

    ExampleAggregate.publish(aggregate, interesting, uninteresting)
  end

  def handle(%ExampleAggregate{} = aggregate, %Pause{}),
    do: ExampleAggregate.pause(aggregate)

  def handle(%ExampleAggregate{} = aggregate, %Stop{}),
    do: ExampleAggregate.stop(aggregate)

  def handle(%ExampleAggregate{} = aggregate, %Continue{}),
    do: ExampleAggregate.continue(aggregate)

  def handle(%ExampleAggregate{} = aggregate, %Error{}),
    do: ExampleAggregate.error(aggregate)

  def handle(%ExampleAggregate{} = aggregate, %Raise{}),
    do: ExampleAggregate.raise(aggregate)
end
