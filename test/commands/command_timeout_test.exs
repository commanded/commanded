defmodule Commanded.Commands.CommandTimeoutTest do
  use Commanded.StorageCase
  doctest Commanded.Commands.Router

  defmodule StubAggregateRoot, do: defstruct []
  defmodule TimeoutCommand, do: defstruct [aggregate_uuid: nil, sleep_in_ms: nil]

  defmodule TimeoutCommandHandler do
    @behaviour Commanded.Commands.Handler

    def handle(%StubAggregateRoot{}, %TimeoutCommand{sleep_in_ms: sleep_in_ms}) do
      :timer.sleep(sleep_in_ms)
      []
    end
  end

  defmodule TimeoutRouter do
    use Commanded.Commands.Router

    dispatch TimeoutCommand, to: TimeoutCommandHandler, aggregate: StubAggregateRoot, identity: :aggregate_uuid, timeout: 1_000
  end

  test "should allow timeout to be specified during command registration" do
    # handler is set to take longer than the configured timeout
    {:error, :aggregate_execution_timeout} = TimeoutRouter.dispatch(%TimeoutCommand{sleep_in_ms: 2_000})
  end

  test "should succeed when handler completes within configured timeout" do
    :ok = TimeoutRouter.dispatch(%TimeoutCommand{sleep_in_ms: 100})
  end

  test "should succeed when timeout is overridden during dispatch" do
    :ok = TimeoutRouter.dispatch(%TimeoutCommand{sleep_in_ms: 100}, 2_000)
  end
end
