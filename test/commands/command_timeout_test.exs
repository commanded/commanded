defmodule Commanded.Commands.CommandTimeoutTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.Commands.{TimeoutRouter, TimeoutCommand}

  setup do
    start_supervised!(DefaultApp)

    :ok
  end

  test "should allow timeout to be specified during command registration" do
    command = %TimeoutCommand{aggregate_uuid: UUID.uuid4(), sleep_in_ms: 2_000}

    # Handler is set to take longer than the configured timeout
    case TimeoutRouter.dispatch(command, application: DefaultApp) do
      {:error, :aggregate_execution_failed} -> :ok
      {:error, :aggregate_execution_timeout} -> :ok
      reply -> flunk("received an unexpected response: #{inspect(reply)}")
    end
  end

  test "should succeed when handler completes within configured timeout" do
    command = %TimeoutCommand{aggregate_uuid: UUID.uuid4(), sleep_in_ms: 100}

    :ok = TimeoutRouter.dispatch(command, application: DefaultApp)
  end

  test "should succeed when timeout is overridden during dispatch" do
    command = %TimeoutCommand{aggregate_uuid: UUID.uuid4(), sleep_in_ms: 100}

    :ok = TimeoutRouter.dispatch(command, application: DefaultApp, timeout: 2_000)
  end

  test "should accept :infinity as timeout option" do
    command = %TimeoutCommand{aggregate_uuid: UUID.uuid4(), sleep_in_ms: 1}

    :ok = TimeoutRouter.dispatch(command, application: DefaultApp, timeout: :infinity)
  end
end
