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
    Adds up to 1 second of jitter.
  """
  def backoff(_error, _failed_event, %FailureContext{context: context}) do
    context = Map.update(context, :failures, 1, & &1 + 1)
    failures = Map.fetch!(context, :failures)

    base_delay = failures ** 2 * 1000
    jitter = :rand.uniform(1000)
    delay = base_delay + jitter

    {:retry, delay, context}
  end

  @doc """
    Stop everything and be grumpy about it.
  """
  def grump(_error, _failed_event, _failure_context) do
    {:stop, "You have no business coding on the BEAM."}
  end
end
