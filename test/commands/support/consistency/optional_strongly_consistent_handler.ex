defmodule Commanded.Commands.OptionalStronglyConsistentEventHandler do
  use Commanded.Event.Handler,
    name: "OptionalStronglyConsistentEventHandler",
    consistency: :strong

  alias Commanded.Commands.{
    ConsistencyAggregateRoot,
    ConsistencyRouter
  }

  alias ConsistencyAggregateRoot.{
    ConsistencyCommand,
    ConsistencyEvent,
    DispatchRequestedEvent
  }

  def handle(%ConsistencyEvent{delay: delay}, _metadata) do
    :timer.sleep(round(delay / 4))
    :ok
  end

  # handle event by dispatching a command
  def handle(%DispatchRequestedEvent{uuid: uuid, delay: delay}, _metadata) do
    :timer.sleep(round(delay / 4))

    ConsistencyRouter.dispatch(
      %ConsistencyCommand{uuid: uuid, delay: delay},
      consistency: :strong
    )
  end
end
