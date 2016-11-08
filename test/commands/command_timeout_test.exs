defmodule Commanded.Commands.CommandTimeoutTest do
  use Commanded.StorageCase
  doctest Commanded.Commands.Router

  defmodule StubAggregateRoot do
    use EventSourced.AggregateRoot, fields: []
  end

  defmodule TimeoutCommand do
    defstruct aggregate_uuid: UUID.uuid4, sleep_in_ms: nil
  end

  defmodule TimeoutCommandHandler do
    @behaviour Commanded.Commands.Handler

    def handle(%StubAggregateRoot{} = aggregate, %TimeoutCommand{sleep_in_ms: sleep_in_ms}) do
      :timer.sleep(sleep_in_ms)
      {:ok, aggregate}
    end
  end

  defmodule TimeoutRouter do
    use Commanded.Commands.Router

    dispatch TimeoutCommand, to: TimeoutCommandHandler, aggregate: StubAggregateRoot, identity: :aggregate_uuid, timeout: 500
  end

  test "should allow timeout to be specified during command registration" do
    {_pid, ref} = spawn_monitor(fn ->
      # handler is set to take longer than the configured timeout (1s sleep vs 500ms timeout)
      :ok = TimeoutRouter.dispatch(%TimeoutCommand{sleep_in_ms: 1_000})
    end)
    assert_receive {:DOWN, ^ref, :process, _, {:timeout, _}}, 1_000
  end

  test "should succeed when handler completes within configured timeout" do
    :ok = TimeoutRouter.dispatch(%TimeoutCommand{sleep_in_ms: 200})
  end

  test "should succeed when timeout is overridden during dispatch" do
    :ok = TimeoutRouter.dispatch(%TimeoutCommand{sleep_in_ms: 1_00}, 2_000)
  end
end
