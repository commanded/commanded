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
    # Simulate slow event handler
    :timer.sleep(:infinity)

    :ok
  end

  # Handle event by dispatching a command.
  def handle(%DispatchRequestedEvent{uuid: uuid, delay: delay}, _metadata) do
    command = %ConsistencyCommand{uuid: uuid, delay: delay}

    ConsistencyRouter.dispatch(command, application: Commanded.DefaultApp)
  end
end
