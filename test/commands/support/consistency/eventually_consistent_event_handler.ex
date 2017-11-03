defmodule Commanded.Commands.EventuallyConsistentEventHandler do
  use Commanded.Event.Handler,
    name: "EventuallyConsistentEventHandler",
    consistency: :eventual

  alias Commanded.Commands.{
    ConsistencyAggregateRoot,
    ConsistencyRouter,
  }
  alias ConsistencyAggregateRoot.{
    ConsistencyCommand,
    ConsistencyEvent,
    DispatchRequestedEvent,
  }

  def handle(%ConsistencyEvent{}, _metadata) do
    :timer.sleep(:infinity) # simulate slow event handler
    :ok
  end

  # handle event by dispatching a command
  def handle(%DispatchRequestedEvent{uuid: uuid, delay: delay}, _metadata) do
    ConsistencyRouter.dispatch(%ConsistencyCommand{uuid: uuid, delay: delay})
  end
end
