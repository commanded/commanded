defmodule Commanded.ProcessManagers.ExampleProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.ExampleAggregate.Commands.Stop

  alias Commanded.ProcessManagers.ExampleAggregate.Events.{
    Errored,
    Interested,
    Paused,
    Raised,
    Started,
    Stopped
  }

  alias Commanded.ProcessManagers.ExampleApp
  alias Commanded.ProcessManagers.ExampleProcessManager

  use Commanded.ProcessManagers.ProcessManager,
    application: ExampleApp,
    name: "ExampleProcessManager"

  @derive Jason.Encoder
  defstruct [:status, items: []]

  def interested?(%Started{aggregate_uuid: aggregate_uuid}), do: {:start, aggregate_uuid}
  def interested?(%Interested{aggregate_uuid: aggregate_uuid}), do: {:continue, aggregate_uuid}
  def interested?(%Paused{aggregate_uuid: aggregate_uuid}), do: {:continue, aggregate_uuid}
  def interested?(%Errored{aggregate_uuid: aggregate_uuid}), do: {:continue, aggregate_uuid}
  def interested?(%Raised{aggregate_uuid: aggregate_uuid}), do: {:continue, aggregate_uuid}
  def interested?(%Stopped{aggregate_uuid: aggregate_uuid}), do: {:stop, aggregate_uuid}

  def handle(%ExampleProcessManager{}, %Interested{index: 10, aggregate_uuid: aggregate_uuid}) do
    %Stop{aggregate_uuid: aggregate_uuid}
  end

  # Simulate a "stuck" process
  def handle(%ExampleProcessManager{}, %Paused{}) do
    :timer.sleep(:infinity)
  end

  def handle(%ExampleProcessManager{}, %Errored{}), do: {:error, :failed}

  def handle(%ExampleProcessManager{}, %Raised{}), do: raise("failed")

  # State mutators

  def apply(%ExampleProcessManager{} = process_manager, %Started{}) do
    %ExampleProcessManager{process_manager | status: :started}
  end

  def apply(%ExampleProcessManager{items: items} = process_manager, %Interested{index: index}) do
    %ExampleProcessManager{process_manager | items: items ++ [index]}
  end
end
