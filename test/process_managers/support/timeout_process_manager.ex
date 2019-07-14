defmodule Commanded.ProcessManagers.TimeoutProcessManager do
  @moduledoc false

  alias Commanded.ProcessManagers.ExampleAggregate.Events.Started
  alias Commanded.ProcessManagers.ExampleAggregate.Events.Stopped
  alias Commanded.ProcessManagers.ExampleApp
  alias Commanded.ProcessManagers.TimeoutProcessManager

  use Commanded.ProcessManagers.ProcessManager,
    application: ExampleApp,
    name: "TimeoutProcessManager",
    idle_timeout: :timer.minutes(1)

  @derive Jason.Encoder
  defstruct [:status]

  def interested?(%Started{aggregate_uuid: aggregate_uuid}), do: {:start, aggregate_uuid}
  def interested?(%Stopped{aggregate_uuid: aggregate_uuid}), do: {:stop, aggregate_uuid}

  ## State mutators

  def apply(%TimeoutProcessManager{} = pm, %Started{}) do
    %TimeoutProcessManager{pm | status: :started}
  end
end
