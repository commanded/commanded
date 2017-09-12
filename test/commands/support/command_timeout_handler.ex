defmodule Commanded.Commands.TimeoutCommandHandler do
  @moduledoc false
  @behaviour Commanded.Commands.Handler

  alias Commanded.Commands.{TimeoutAggregateRoot,TimeoutCommand}

  def handle(%TimeoutAggregateRoot{}, %TimeoutCommand{sleep_in_ms: sleep_in_ms}) do
    :timer.sleep(sleep_in_ms)
    []
  end
end
