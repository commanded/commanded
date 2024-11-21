defmodule Commanded.Event.ErrorHandler.Backoff do
  require Logger

  alias Commanded.Event.ErrorHandler
  alias Commanded.Event.FailureContext

  @behaviour ErrorHandler

  @impl ErrorHandler
  def handle_error({:error, reason}, _event, %FailureContext{context: context}) do
    context = Map.update(context, :failures, 1, fn failures -> failures + 1 end)
    max_failures = Map.get(context, :max_failures, 10)

    case Map.get(context, :failures) do
      too_many when too_many >= max_failures ->
        Logger.warning("Stopping #{__MODULE__} after too many failures.")
        {:stop, reason}

      failures ->
        base_delay = failures ** 2 * 1000
        jitter = :rand.uniform(1000)
        delay = base_delay + jitter
        Logger.debug("Failure #{failures}, delaying for #{delay}ms")
        {:retry, delay, context}
    end
  end
end
