defmodule Commanded.Event.ErrorHandler do
  alias Commanded.Event.FailureContext

  @doc """
    Stop the `Commanded.Event.Handler` with the reason given.
  """
  def stop_on_error({:error, reason}, _failed_event, _failure_context) do
    {:stop, reason}
  end

  @doc """
    Backoff exponentially when an error is encountered.
    * Adds up to 1 second of jitter.
    * Minimum of 1 second delay
    * Maximum of 24 hour delay
  """
  def backoff(_error, _event, %FailureContext{} = failure_context, opts \\ []) do
    jitter_fn = Keyword.get(opts, :jitter_fn, &one_second_jitter/0)

    %FailureContext{context: context} = failure_context
    context = Map.update(context, :failures, 1, &(&1 + 1))
    failures = Map.fetch!(context, :failures)

    base_delay = failures ** 2 * 1000
    delay = base_delay + jitter_fn.()
    delay = max(delay, :timer.seconds(1))
    delay = min(delay, :timer.hours(24))

    failure_context = %{failure_context | context: context}

    {:retry, delay, failure_context}
  end

  defp one_second_jitter do
    :rand.uniform(1000)
  end
end
