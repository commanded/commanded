defmodule Commanded.Commands.StronglyConsistentProcessManager do
  alias Commanded.Commands.{ConsistencyApp, StronglyConsistentProcessManager}

  use Commanded.ProcessManagers.ProcessManager,
    application: ConsistencyApp,
    name: __MODULE__,
    consistency: :strong

  @derive Jason.Encoder
  defstruct [
    :uuid
  ]

  alias Commanded.Commands.ConsistencyAggregateRoot.{
    ConsistencyCommand,
    ConsistencyEvent,
    DispatchRequestedEvent,
    NoOpCommand
  }

  def interested?(%DispatchRequestedEvent{uuid: uuid}), do: {:start, uuid}
  def interested?(%ConsistencyEvent{uuid: uuid}), do: {:continue, uuid}

  def handle(%StronglyConsistentProcessManager{}, %DispatchRequestedEvent{} = requested) do
    %DispatchRequestedEvent{uuid: uuid, delay: delay} = requested

    %ConsistencyCommand{uuid: uuid, delay: delay}
  end

  def handle(%StronglyConsistentProcessManager{}, %ConsistencyEvent{uuid: uuid, delay: delay}) do
    :timer.sleep(delay)

    %NoOpCommand{uuid: uuid}
  end

  def apply(%StronglyConsistentProcessManager{}, %DispatchRequestedEvent{uuid: uuid}) do
    %StronglyConsistentProcessManager{uuid: uuid}
  end

  def apply(%StronglyConsistentProcessManager{}, %ConsistencyEvent{uuid: uuid}) do
    %StronglyConsistentProcessManager{uuid: uuid}
  end
end
