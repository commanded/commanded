defmodule Commanded.Commands.DispatchConsistencyTest do
  use ExUnit.Case

  alias Commanded.Commands.{
    ConsistencyAggregateRoot,
    ConsistencyPrefixRouter,
    EventuallyConsistentEventHandler,
    ExecutionResult,
    OptionalStronglyConsistentEventHandler,
    StronglyConsistentEventHandler,
    StronglyConsistentProcessManager
  }

  alias Commanded.Commands.ConsistencyApp
  alias Commanded.EventStore
  alias Commanded.UUID
  alias ConsistencyAggregateRoot.ConsistencyCommand
  alias ConsistencyAggregateRoot.NoOpCommand
  alias ConsistencyAggregateRoot.RequestDispatchCommand

  setup do
    start_supervised!(ConsistencyApp)
    :ok
  end

  describe "event handlers" do
    setup [:start_event_handlers]

    test "should wait for strongly consistent event handler to handle event" do
      command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 0}

      assert :ok = ConsistencyApp.dispatch(command, consistency: :strong)
    end

    # default consistency timeout set to 100ms test config
    test "should timeout waiting for strongly consistent event handler to handle event" do
      command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 5_000}

      assert {:error, :consistency_timeout} =
               ConsistencyApp.dispatch(command, consistency: :strong)
    end

    test "should not wait when command creates no events" do
      command = %NoOpCommand{uuid: UUID.uuid4()}

      assert :ok = ConsistencyApp.dispatch(command, consistency: :strong)
    end

    test "should allow strongly consistent event handler to dispatch a command" do
      command = %RequestDispatchCommand{uuid: UUID.uuid4(), delay: 0}

      assert :ok = ConsistencyApp.dispatch(command, consistency: :strong)
    end

    test "should timeout waiting for strongly consistent handler dispatching a command" do
      command = %RequestDispatchCommand{uuid: UUID.uuid4(), delay: 5_000}

      assert {:error, :consistency_timeout} =
               ConsistencyApp.dispatch(command, consistency: :strong)
    end
  end

  describe "optional `:strong` consistency" do
    setup [:start_event_handlers, :start_optional_handler]

    test "should only wait for opt-in strongly consistent event handler to handle event" do
      command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 100}
      opts = [application: ConsistencyApp, consistency: [OptionalStronglyConsistentEventHandler]]

      assert :ok = ConsistencyApp.dispatch(command, opts)
    end

    # Default consistency timeout set to 100ms test config
    test "should timeout waiting for strongly consistent event handler to handle event" do
      command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 5_000}

      opts = [
        application: ConsistencyApp,
        consistency: ["OptionalStronglyConsistentEventHandler"]
      ]

      assert {:error, :consistency_timeout} = ConsistencyApp.dispatch(command, opts)
    end
  end

  describe "aggregate identity prefix" do
    setup :start_event_handlers

    test "should wait for strongly consistent event handler to handle event" do
      uuid = UUID.uuid4()
      command = %ConsistencyCommand{uuid: uuid, delay: 0}

      assert :ok =
               ConsistencyPrefixRouter.dispatch(command,
                 application: ConsistencyApp,
                 consistency: :strong
               )
    end

    test "should append events to stream using prefixed aggregate uuid" do
      uuid = UUID.uuid4()
      command = %ConsistencyCommand{uuid: uuid, delay: 0}

      assert {:ok, %ExecutionResult{aggregate_uuid: aggregate_uuid}} =
               ConsistencyPrefixRouter.dispatch(command,
                 application: ConsistencyApp,
                 consistency: :strong,
                 include_execution_result: true
               )

      assert aggregate_uuid == "example-prefix-" <> uuid

      recorded_events =
        EventStore.stream_forward(ConsistencyApp, aggregate_uuid) |> Enum.to_list()

      assert length(recorded_events) == 1
    end
  end

  describe "process manager consistency" do
    setup :start_process_manager

    test "should successfully dispatch command" do
      command = %RequestDispatchCommand{uuid: UUID.uuid4(), delay: 5_000}

      assert :ok = ConsistencyApp.dispatch(command, consistency: :strong)
    end
  end

  def start_event_handlers(_context) do
    start_supervised!(StronglyConsistentEventHandler, shutdown: :brutal_kill)
    start_supervised!(EventuallyConsistentEventHandler, shutdown: :brutal_kill)

    :ok
  end

  def start_optional_handler(_context) do
    start_supervised!(OptionalStronglyConsistentEventHandler)

    :ok
  end

  def start_process_manager(_context) do
    start_supervised!(StronglyConsistentProcessManager)

    :ok
  end
end
