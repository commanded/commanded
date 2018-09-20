defmodule Commanded.Commands.CommandTimeoutTest do
  use Commanded.StorageCase

  alias Commanded.Commands.{TimeoutRouter, TimeoutCommand}

  test "should allow timeout to be specified during command registration" do
    # handler is set to take longer than the configured timeout
    case TimeoutRouter.dispatch(%TimeoutCommand{aggregate_uuid: UUID.uuid4(), sleep_in_ms: 2_000}) do
      {:error, :aggregate_execution_failed} -> :ok
      {:error, :aggregate_execution_timeout} -> :ok
      reply -> flunk("received an unexpected response: #{inspect(reply)}")
    end
  end

  test "should succeed when handler completes within configured timeout" do
    :ok = TimeoutRouter.dispatch(%TimeoutCommand{aggregate_uuid: UUID.uuid4(), sleep_in_ms: 100})
  end

  test "should succeed when timeout is overridden during dispatch" do
    :ok =
      TimeoutRouter.dispatch(
        %TimeoutCommand{aggregate_uuid: UUID.uuid4(), sleep_in_ms: 100},
        2_000
      )
  end
end
