defmodule Commanded.Commands.DispatchConsistencyTest do
  use Commanded.StorageCase

  defmodule ConsistencyCommand do
    defstruct [:uuid, :delay]
  end

  defmodule NoOpCommand do
    defstruct [:uuid]
  end

  defmodule ConsistencyEvent do
    defstruct [:delay]
  end

  defmodule ConsistencyAggregateRoot do
    defstruct [:delay]

    def execute(%ConsistencyAggregateRoot{}, %ConsistencyCommand{delay: delay}) do
      %ConsistencyEvent{delay: delay}
    end

    def execute(%ConsistencyAggregateRoot{}, %NoOpCommand{}), do: []

    def apply(%ConsistencyAggregateRoot{} = aggregate, %ConsistencyEvent{delay: delay}) do
      %ConsistencyAggregateRoot{aggregate | delay: delay}
    end
  end

  defmodule ConsistencyRouter do
    use Commanded.Commands.Router

    dispatch [NoOpCommand,ConsistencyCommand],
      to: ConsistencyAggregateRoot,
      identity: :uuid
  end

  defmodule StronglyConsistentEventHandler do
    use Commanded.Event.Handler,
      name: "StronglyConsistentEventHandler",
      consistency: :strong

    def handle(%ConsistencyEvent{delay: delay}, _metadata) do
      :timer.sleep(delay)
      :ok
    end
  end

  defmodule EventuallyConsistentEventHandler do
    use Commanded.Event.Handler,
      name: "EventuallyConsistentEventHandler",
      consistency: :eventual

    def handle(%ConsistencyEvent{}, _metadata) do
      :timer.sleep(:infinity) # simulate slow event handler
      :ok
    end
  end

  setup do
    {:ok, handler1} = StronglyConsistentEventHandler.start_link()
    {:ok, handler2} = EventuallyConsistentEventHandler.start_link()

    on_exit fn ->
      Commanded.Helpers.Process.shutdown(handler1)
      Commanded.Helpers.Process.shutdown(handler2)
    end

    :ok
  end

  test "should wait for strongly consistent event handler to handle event" do
    command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 0}
    assert :ok = ConsistencyRouter.dispatch(command, consistency: :strong)
  end

  # default consistency timeout set to 100ms test config
  test "should timeout waiting for strongly consistent event handler to handle event" do
    command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 5_000}
    assert {:error, :consistency_timeout} =  ConsistencyRouter.dispatch(command, consistency: :strong)
  end

  test "should not wait when command creates no events" do
    assert :ok = ConsistencyRouter.dispatch(%NoOpCommand{uuid: UUID.uuid4()}, consistency: :strong)
  end
end
