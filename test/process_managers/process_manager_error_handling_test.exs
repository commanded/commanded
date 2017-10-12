defmodule Commanded.ProcessManager.ProcessManagerErrorHandlingTest do
  use Commanded.StorageCase

  alias Commanded.Helpers
  alias Commanded.Helpers.Wait
  alias Commanded.ProcessManagers.{ProcessRouter,ProcessManagerInstance}

  import Commanded.Assertions.EventAssertions

  defmodule ExampleAggregate do
    defstruct [:process_uuid]

    defmodule Commands do
      defmodule StartProcess, do: defstruct [:process_uuid, :reply_to]
      defmodule AttemptProcess, do: defstruct [:process_uuid, :reply_to]
    end

    defmodule Events do
      defmodule ProcessStarted, do: defstruct [:process_uuid, :reply_to]
    end

    alias Commands.{StartProcess,AttemptProcess}
    alias Events.{ProcessStarted,ProcessResumed}

    def execute(%ExampleAggregate{}, %StartProcess{process_uuid: process_uuid, reply_to: reply_to}) do
      %ProcessStarted{process_uuid: process_uuid, reply_to: reply_to}
    end

    def execute(%ExampleAggregate{}, %AttemptProcess{}), do: {:error, :failed}

    def apply(%ExampleAggregate{} = aggregate, %ProcessStarted{}), do: aggregate
  end

  alias ExampleAggregate.Commands.{StartProcess,AttemptProcess}
  alias ExampleAggregate.Events.{ProcessStarted}

  defmodule ExampleRouter do
    use Commanded.Commands.Router

    dispatch [StartProcess,AttemptProcess],
      to: ExampleAggregate, identity: :process_uuid
  end

  defmodule ErrorHandlingProcessManager do
    use Commanded.ProcessManagers.ProcessManager,
      name: "ErrorHandlingProcessManager",
      router: ExampleRouter

    defstruct [:process_uuid]

    alias ExampleAggregate.Events.ProcessStarted

    def interested?(%ProcessStarted{process_uuid: process_uuid}), do: {:start, process_uuid}

    def handle(%ErrorHandlingProcessManager{}, %ProcessStarted{process_uuid: process_uuid, reply_to: reply_to}) do
      %AttemptProcess{process_uuid: process_uuid, reply_to: reply_to}
    end

    def error({:error, :failed}, %AttemptProcess{reply_to: reply_to}, %{attempts: attempts} = context) when attempts >= 3 do
      send(reply_to, {:error, :too_many_attempts, context})

      {:stop, :too_many_attempts}
    end

    def error({:error, :failed}, %AttemptProcess{reply_to: reply_to}, context) do
      send(reply_to, {:error, :failed, context})

      attempts = Map.get(context, :attempts, 0)
      {:retry, Map.put(context, :attempts, attempts + 1)}
    end
  end

  @tag :wip
  test "should retry the event until process manager requests stop" do
    process_uuid = UUID.uuid4()

    {:ok, process_router} = ErrorHandlingProcessManager.start_link()

    command = %StartProcess{process_uuid: process_uuid, reply_to: self()}

    assert :ok = ExampleRouter.dispatch(command)

    assert_receive {:error, :failed, %{}}
    assert_receive {:error, :failed, %{attempts: 1}}
    assert_receive {:error, :failed, %{attempts: 2}}
    assert_receive {:error, :too_many_attempts, %{attempts: 3}}
  end
end
