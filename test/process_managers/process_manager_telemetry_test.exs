defmodule Commanded.ProcessManagers.ProcessManagerTelemetryTest do
  use ExUnit.Case

  import Mox

  alias Commanded.ProcessManagers.ProcessManagerInstance
  alias Commanded.UUID

  setup :set_mox_global
  setup :verify_on_exit!

  defmodule Commands do
    defmodule Ok do
      defstruct [:message]
    end
  end

  defmodule Event do
    @derive Jason.Encoder
    defstruct [:message, :type]
  end

  defmodule Agg do
    defstruct []

    def execute(_, _) do
      []
    end

    def apply(_, _) do
      %__MODULE__{}
    end
  end

  defmodule Router do
    use Commanded.Commands.Router

    dispatch(Commands.Ok, to: Agg, identity: :message)
  end

  defmodule App do
    alias Commanded.EventStore.Adapters.InMemory
    alias Commanded.Serialization.JsonSerializer

    use Commanded.Application,
      otp_app: :app,
      event_store: [
        adapter: InMemory,
        serializer: JsonSerializer
      ],
      pubsub: :local,
      registry: :local

    router Router
  end

  defmodule ExamplePM do
    use Commanded.ProcessManagers.ProcessManager,
      application: App,
      name: __MODULE__

    alias Commands.Ok

    @derive Jason.Encoder
    defstruct message: "init"

    def handle(%ExamplePM{}, %Event{type: type, message: message}) do
      case type do
        "ok" -> %Ok{message: message}
        "error" -> {:error, message}
        "retry" -> {:error, :retry}
        "raise" -> raise message
      end
    end

    def apply(%ExamplePM{}, %Event{message: message}),
      do: %ExamplePM{message: message}

    def error({:error, :retry}, %Event{}, failure_context) do
      if failure_context.context[:retried?] do
        :skip
      else
        {:retry, %{retried?: true}}
      end
    end
  end

  alias Commands.Ok

  setup do
    start_supervised!(App)

    attach_telemetry()

    :ok
  end

  @handler "test-pm-handler"

  describe "process manager telemetry" do
    test "emit `[:commanded, :process_manager, :handle, :start]` event" do
      uuid = UUID.uuid4()

      {:ok, instance} = start_process_manager_instance(uuid)

      event = to_recorded_event(%Event{message: "start", type: "ok"})

      :ok = ProcessManagerInstance.process_event(instance, event)

      assert_receive {[:commanded, :process_manager, :handle, :start], 1, measurements, metadata}

      assert match?(%{system_time: _system_time}, measurements)

      assert match?(
               %{
                 application: App,
                 process_manager_module: ExamplePM,
                 process_manager_name: "ExamplePM",
                 process_state: %ExamplePM{message: "init"},
                 process_uuid: ^uuid,
                 recorded_event: ^event
               },
               metadata
             )

      assert_receive {[:commanded, :process_manager, :handle, :stop], 2, _measurements, _metadata}

      refute_receive {[:commanded, :process_manager, :handle, :exception], _, _measurements,
                      _metadata}
    end

    test "emit `[:commanded, :process_manager, :handle, :stop]` event" do
      uuid = UUID.uuid4()

      {:ok, instance} = start_process_manager_instance(uuid)

      event = to_recorded_event(%Event{message: "start", type: "ok"})

      :ok = ProcessManagerInstance.process_event(instance, event)

      assert_receive {[:commanded, :process_manager, :handle, :start], 1, _measurements,
                      _metadata}

      assert_receive {[:commanded, :process_manager, :handle, :stop], 2, measurements, metadata}

      assert match?(%{duration: _}, measurements)
      assert is_integer(measurements.duration)

      assert match?(
               %{
                 application: App,
                 process_manager_module: ExamplePM,
                 process_manager_name: "ExamplePM",
                 process_state: %ExamplePM{message: "init"},
                 process_uuid: ^uuid,
                 recorded_event: ^event,
                 commands: [%Ok{message: "start"}]
               },
               metadata
             )

      refute_receive {[:commanded, :process_manager, :handle, :exception], _num, _measurements,
                      _metadata}
    end

    test "emit `[:commanded, :process_manager, :handle, :stop]` with error event" do
      uuid = UUID.uuid4()

      {:ok, instance} = start_process_manager_instance(uuid)

      event = to_recorded_event(%Event{message: "stop", type: "error"})

      :ok = ProcessManagerInstance.process_event(instance, event)

      assert_receive {[:commanded, :process_manager, :handle, :start], 1, _measurements,
                      _metadata}

      assert_receive {[:commanded, :process_manager, :handle, :stop], 2, measurements, metadata}

      assert match?(%{duration: _}, measurements)
      assert is_integer(measurements.duration)

      assert match?(
               %{
                 application: App,
                 process_manager_module: ExamplePM,
                 process_manager_name: "ExamplePM",
                 process_state: %ExamplePM{message: "init"},
                 process_uuid: ^uuid,
                 recorded_event: ^event,
                 error: "stop"
               },
               metadata
             )

      refute_receive {[:commanded, :process_manager, :handle, :exception], _num, _measurements,
                      _metadata}
    end

    test "events are emitted with discrete start/stop on retries" do
      uuid = UUID.uuid4()

      {:ok, instance} = start_process_manager_instance(uuid)

      event = to_recorded_event(%Event{message: "retry", type: "retry"})

      :ok = ProcessManagerInstance.process_event(instance, event)

      assert_receive {[:commanded, :process_manager, :handle, :start], 1, _measurements,
                      _metadata}

      assert_receive {[:commanded, :process_manager, :handle, :stop], 2, measurements, metadata}

      assert match?(%{duration: _}, measurements)
      assert is_integer(measurements.duration)

      assert match?(
               %{
                 application: App,
                 process_manager_module: ExamplePM,
                 process_manager_name: "ExamplePM",
                 process_state: %ExamplePM{message: "init"},
                 process_uuid: ^uuid,
                 recorded_event: ^event,
                 error: :retry
               },
               metadata
             )

      refute_receive {[:commanded, :process_manager, :handle, :exception], _num, _measurements,
                      _metadata}

      assert_receive {[:commanded, :process_manager, :handle, :start], 3, _measurements,
                      _metadata}

      assert_receive {[:commanded, :process_manager, :handle, :stop], 4, _measurements, _metadata}
    end

    @tag capture_log: true
    test "emit `[:commanded, :process_manager, :handle, :exception]` event" do
      uuid = UUID.uuid4()

      {:ok, instance} = start_process_manager_instance(uuid)

      event = to_recorded_event(%Event{message: "exception", type: "raise"})

      :ok = ProcessManagerInstance.process_event(instance, event)

      assert_receive {[:commanded, :process_manager, :handle, :start], 1, _measurements,
                      _metadata}

      refute_receive {[:commanded, :process_manager, :handle, :stop], _num, _measurements,
                      _metadata}

      assert_receive {[:commanded, :process_manager, :handle, :exception], 2, measurements,
                      metadata}

      assert match?(%{duration: _}, measurements)
      assert is_integer(measurements.duration)

      assert match?(
               %{
                 application: App,
                 process_manager_module: ExamplePM,
                 process_manager_name: "ExamplePM",
                 process_state: %ExamplePM{message: "init"},
                 process_uuid: ^uuid,
                 recorded_event: ^event,
                 kind: :error,
                 reason: %RuntimeError{message: "exception"},
                 stacktrace: _
               },
               metadata
             )
    end
  end

  defp attach_telemetry do
    agent = start_supervised!({Agent, fn -> 1 end})

    :telemetry.attach_many(
      @handler,
      [
        [:commanded, :process_manager, :handle, :start],
        [:commanded, :process_manager, :handle, :stop],
        [:commanded, :process_manager, :handle, :exception]
      ],
      fn event_name, measurements, metadata, reply_to ->
        num = Agent.get_and_update(agent, fn num -> {num, num + 1} end)
        send(reply_to, {event_name, num, measurements, metadata})
      end,
      self()
    )

    on_exit(fn ->
      :telemetry.detach(@handler)
    end)
  end

  defp start_process_manager_instance(transfer_uuid) do
    start_supervised(
      {ProcessManagerInstance,
       application: App,
       idle_timeout: :infinity,
       process_manager_name: "ExamplePM",
       process_manager_module: ExamplePM,
       process_router: self(),
       process_uuid: transfer_uuid}
    )
  end

  defp to_recorded_event(event) do
    alias Commanded.EventStore.RecordedEvent

    %RecordedEvent{event_number: 1, stream_id: "stream-id", stream_version: 1, data: event}
  end
end
