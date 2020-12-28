defmodule Commanded.Commands.EventuallyConsistentEventHandler do
  use Commanded.Event.Handler,
    application: Commanded.Commands.ConsistencyApp,
    name: "EventuallyConsistentEventHandler",
    consistency: :eventual

  alias Commanded.Commands.ConsistencyApp
  alias Commanded.Commands.ConsistencyAggregateRoot
  alias ConsistencyAggregateRoot.{ConsistencyCommand, ConsistencyEvent, DispatchRequestedEvent}

  # Simulate slow event handler.
  def handle(%ConsistencyEvent{}, _metadata) do
    :timer.sleep(:infinity)

    :ok
  end

  # Dispatch a command.
  def handle(%DispatchRequestedEvent{uuid: uuid, delay: delay}, _metadata) do
    command = %ConsistencyCommand{uuid: uuid, delay: delay}

    ConsistencyApp.dispatch(command)
  end
end
