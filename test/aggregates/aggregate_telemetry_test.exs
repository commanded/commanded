defmodule Commanded.Aggregates.AggregateTelemetryTest do
  use ExUnit.Case

  alias Commanded.Aggregates.{Aggregate, ExecutionContext}
  alias Commanded.{DefaultApp, UUID}

  defmodule Commands do
    defmodule Ok do
      defstruct [:message]
    end

    defmodule Error do
      defstruct [:message]
    end

    defmodule RaiseException do
      defstruct [:message]
    end
  end

  defmodule Event do
    @derive Jason.Encoder
    defstruct [:message]
  end

  defmodule ExampleAggregate do
    alias Commands.{Error, Ok, RaiseException}

    defstruct [:message]

    def execute(%ExampleAggregate{}, %Ok{message: message}), do: %Event{message: message}
    def execute(%ExampleAggregate{}, %Error{message: message}), do: {:error, message}
    def execute(%ExampleAggregate{}, %RaiseException{message: message}), do: raise(message)

    def apply(%ExampleAggregate{}, %Event{message: message}),
      do: %ExampleAggregate{message: message}
  end

  alias Commands.{Error, Ok, RaiseException}

  setup do
    start_supervised!(DefaultApp)
    attach_telemetry()
    :ok
  end

  describe "aggregate telemetry" do
    setup do
      aggregate_uuid = UUID.uuid4()

      {:ok, pid} = start_aggregate(aggregate_uuid)

      [aggregate_uuid: aggregate_uuid, pid: pid]
    end

    test "emit `[:commanded, :aggregate, :execute, :start]` event",
         %{aggregate_uuid: aggregate_uuid, pid: pid} do
      context = %ExecutionContext{
        command: %Ok{message: "ok"},
        function: :execute,
        handler: ExampleAggregate
      }

      self = self()

      {:ok, 1, _events} = GenServer.call(pid, {:execute_command, context})

      assert_receive {[:commanded, :aggregate, :execute, :start], measurements, metadata}

      assert match?(%{system_time: _system_time}, measurements)
      assert is_number(measurements.system_time)

      assert match?(
               %{
                 aggregate_state: %ExampleAggregate{},
                 aggregate_uuid: ^aggregate_uuid,
                 aggregate_version: 0,
                 application: Commanded.DefaultApp,
                 caller: ^self,
                 execution_context: ^context
               },
               metadata
             )

      assert_receive {[:commanded, :aggregate, :execute, :stop], _measurements, _metadata}
      refute_received {[:commanded, :aggregate, :execute, :exception], _measurements, _metadata}
    end

    test "emit `[:commanded, :aggregate, :execute, :stop]` event",
         %{aggregate_uuid: aggregate_uuid, pid: pid} do
      context = %ExecutionContext{
        command: %Ok{message: "ok"},
        function: :execute,
        handler: ExampleAggregate
      }

      self = self()

      {:ok, 1, events} = GenServer.call(pid, {:execute_command, context})

      assert_receive {[:commanded, :aggregate, :execute, :start], _measurements, _metadata}
      assert_receive {[:commanded, :aggregate, :execute, :stop], measurements, metadata}

      assert match?(%{duration: _duration}, measurements)
      assert is_number(measurements.duration)

      assert match?(
               %{
                 aggregate_state: %ExampleAggregate{message: "ok"},
                 aggregate_uuid: ^aggregate_uuid,
                 aggregate_version: 1,
                 application: Commanded.DefaultApp,
                 caller: ^self,
                 execution_context: ^context,
                 events: ^events
               },
               metadata
             )

      refute_received {[:commanded, :aggregate, :execute, :exception], _measurements, _metadata}
    end

    test "emit `[:commanded, :aggregate, :execute, :stop]` with error event",
         %{aggregate_uuid: aggregate_uuid, pid: pid} do
      context = %ExecutionContext{
        command: %Error{message: "an error"},
        function: :execute,
        handler: ExampleAggregate
      }

      self = self()

      {:error, "an error"} = GenServer.call(pid, {:execute_command, context})

      assert_receive {[:commanded, :aggregate, :execute, :start], _measurements, _metadata}
      assert_receive {[:commanded, :aggregate, :execute, :stop], measurements, metadata}

      assert match?(%{duration: _duration}, measurements)
      assert is_number(measurements.duration)

      assert match?(
               %{
                 aggregate_state: %ExampleAggregate{},
                 aggregate_uuid: ^aggregate_uuid,
                 aggregate_version: 0,
                 application: Commanded.DefaultApp,
                 caller: ^self,
                 execution_context: ^context,
                 error: "an error"
               },
               metadata
             )

      refute_received {[:commanded, :aggregate, :execute, :exception], _measurements, _metadata}
    end

    test "emit `[:commanded, :aggregate, :execute, :exception]` event",
         %{aggregate_uuid: aggregate_uuid, pid: pid} do
      context = %ExecutionContext{
        command: %RaiseException{message: "an exception"},
        function: :execute,
        handler: ExampleAggregate
      }

      self = self()

      Process.unlink(pid)

      {:error, %RuntimeError{message: "an exception"}} =
        GenServer.call(pid, {:execute_command, context})

      assert_receive {[:commanded, :aggregate, :execute, :start], _measurements, _metadata}
      assert_receive {[:commanded, :aggregate, :execute, :exception], measurements, metadata}

      assert match?(%{duration: _duration}, measurements)
      assert is_number(measurements.duration)

      assert match?(
               %{
                 aggregate_state: %ExampleAggregate{},
                 aggregate_uuid: ^aggregate_uuid,
                 aggregate_version: 0,
                 application: Commanded.DefaultApp,
                 caller: ^self,
                 execution_context: ^context,
                 kind: :error,
                 reason: %RuntimeError{message: "an exception"},
                 stacktrace: _stacktrace
               },
               metadata
             )

      refute_received {[:commanded, :aggregate, :execute, :stop], _measurements, _metadata}
    end
  end

  def start_aggregate(aggregate_uuid) do
    Aggregate.start_link([application: DefaultApp],
      aggregate_module: ExampleAggregate,
      aggregate_uuid: aggregate_uuid
    )
  end

  defp attach_telemetry do
    :telemetry.attach_many(
      "test-handler",
      [
        [:commanded, :aggregate, :execute, :start],
        [:commanded, :aggregate, :execute, :stop],
        [:commanded, :aggregate, :execute, :exception]
      ],
      fn event_name, measurements, metadata, reply_to ->
        send(reply_to, {event_name, measurements, metadata})
      end,
      self()
    )

    on_exit(fn ->
      :telemetry.detach("test-handler")
    end)
  end
end
