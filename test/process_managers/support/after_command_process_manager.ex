defmodule Commanded.ProcessManagers.AfterCommandProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.AfterCommandProcessManager
  alias Commanded.ProcessManagers.ExampleAggregate.Commands.{Stop, Continue}
  alias Commanded.ProcessManagers.ExampleAggregate.Events.{Interested, Started}
  alias Commanded.ProcessManagers.ExampleApp

  use Commanded.ProcessManagers.ProcessManager,
    application: ExampleApp,
    name: "AfterCommandProcessManager"

  @derive Jason.Encoder
  defstruct [:status, items: []]

  def interested?(%Started{aggregate_uuid: aggregate_uuid}, _metadata),
    do: {:start, aggregate_uuid}

  def interested?(%Interested{aggregate_uuid: aggregate_uuid}, _metadata),
    do: {:continue, aggregate_uuid}

  def handle(%AfterCommandProcessManager{}, %Interested{index: 1, aggregate_uuid: aggregate_uuid}) do
    %Continue{aggregate_uuid: aggregate_uuid}
  end

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

  # after_command/2 callback
  def after_command(%AfterCommandProcessManager{}, %Stop{}) do
    :stop
  end

  # after_command/3 callback
  def after_command(%AfterCommandProcessManager{}, %Continue{}, metadata) do
    %{"notify_to" => notify_to_pid_as_bse64} = metadata

    pid =
      notify_to_pid_as_bse64
      |> Base.decode64!()
      |> :erlang.binary_to_term()

    Process.send(pid, :metadata_available, [])

    :continue
  end
end
