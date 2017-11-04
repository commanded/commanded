defmodule Commanded.Commands.StronglyConsistentEventHandler do
  use Commanded.Event.Handler,
    name: "StronglyConsistentEventHandler",
    consistency: :strong

  alias Commanded.Commands.{
    ConsistencyAggregateRoot,
    ConsistencyRouter,
  }
  alias ConsistencyAggregateRoot.{
    ConsistencyCommand,
    ConsistencyEvent,
    DispatchRequestedEvent,
  }

  def handle(%ConsistencyEvent{delay: delay}, _metadata) do
    :timer.sleep(delay)
    :ok
  end

  # handle event by dispatching a command
  def handle(%DispatchRequestedEvent{uuid: uuid, delay: delay}, _metadata) do
    :timer.sleep(delay)
    ConsistencyRouter.dispatch(%ConsistencyCommand{uuid: uuid, delay: delay}, consistency: :strong)
  end
end
