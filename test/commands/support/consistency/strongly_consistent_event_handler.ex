defmodule Commanded.Commands.StronglyConsistentEventHandler do
  use Commanded.Event.Handler,
    application: Commanded.Commands.ConsistencyApp,
    name: "StronglyConsistentEventHandler",
    consistency: :strong

  alias Commanded.Commands.{ConsistencyAggregateRoot, ConsistencyApp}
  alias ConsistencyAggregateRoot.{ConsistencyCommand, ConsistencyEvent, DispatchRequestedEvent}

  # Dispatch a command with consistency `:strong` after an optional delay.
  def handle(%DispatchRequestedEvent{uuid: uuid, delay: delay}, _metadata) do
    :timer.sleep(delay)

    command = %ConsistencyCommand{uuid: uuid, delay: delay}

    ConsistencyApp.dispatch(command, consistency: :strong)
  end

  # Block for a requested delay.
  def handle(%ConsistencyEvent{delay: delay}, _metadata) do
    :timer.sleep(delay)

    :ok
  end
end
