defmodule Commanded.Commands.EventuallyConsistentEventHandler do
  use Commanded.Event.Handler,
    application: Commanded.DefaultApp,
    name: "EventuallyConsistentEventHandler",
    consistency: :eventual

  alias Commanded.Commands.{
    ConsistencyAggregateRoot,
    ConsistencyRouter
  }

  alias ConsistencyAggregateRoot.{
    ConsistencyCommand,
    ConsistencyEvent,
    DispatchRequestedEvent
  }

  def handle(%ConsistencyEvent{}, _metadata) do
    # simulate slow event handler
    :timer.sleep(:infinity)
    :ok
  end

  # handle event by dispatching a command
  def handle(%DispatchRequestedEvent{uuid: uuid, delay: delay}, _metadata) do
    ConsistencyRouter.dispatch(%ConsistencyCommand{uuid: uuid, delay: delay})
  end
end
