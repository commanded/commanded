defmodule Commanded.ProcessManagers.AfterCommandProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.AfterCommandProcessManager
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.Stop
  alias Commanded.ProcessManagers.ExampleAggregate.Events.{Interested, Started}
  alias Commanded.ProcessManagers.ExampleApp

  use Commanded.ProcessManagers.ProcessManager,
    application: ExampleApp,
    name: "AfterCommandProcessManager"

  @derive Jason.Encoder
  defstruct [:status, items: []]

  def interested?(%Started{aggregate_uuid: aggregate_uuid}), do: {:start, aggregate_uuid}
  def interested?(%Interested{aggregate_uuid: aggregate_uuid}), do: {:continue, aggregate_uuid}

  def handle(%AfterCommandProcessManager{}, %Interested{index: 10, aggregate_uuid: aggregate_uuid}) do
    %Stop{aggregate_uuid: aggregate_uuid}
  end

  # State mutators

  def apply(%AfterCommandProcessManager{} = process_manager, %Started{}) do
    %AfterCommandProcessManager{process_manager | status: :started}
  end

  def apply(%AfterCommandProcessManager{items: items} = process_manager, %Interested{index: index}) do
    %AfterCommandProcessManager{process_manager | items: items ++ [index]}
  end

  def after_command(%AfterCommandProcessManager{}, %Stop{}) do
    :stop
  end
end
