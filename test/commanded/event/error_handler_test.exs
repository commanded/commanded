defmodule Commanded.Event.ErrorHandlerTest do
  use ExUnit.Case

  alias Commanded.Event.ErrorHandler
  alias Commanded.Event.FailureContext

  defmodule Event do
    defstruct [:id]
  end

  test "Stop on error" do
    context = %FailureContext{}
    error = {:error, "an error"}

    result = ErrorHandler.stop_on_error(error, an_event(), context)
    assert result == {:stop, "an error"}
  end

  describe "backoff" do
    test "the first delay is 1 second" do
      context = %FailureContext{context: %{}}

      {:retry, delay, context} =
        ErrorHandler.backoff(an_error(), an_event(), context, no_jitter())

      assert context.context.failures == 1
      assert delay == :timer.seconds(1)
    end

    test "applies jitter to delay" do
      jitter_fn = fn -> 234 end

      {:retry, delay, _} =
        ErrorHandler.backoff(an_error(), an_event(), failure_context(), jitter_fn)

      assert delay == 1234
    end

    test "backs off exponentially-ish" do
      failure_context = %FailureContext{context: %{}}

      expectations = [
        {1, 1_000},
        {2, 4_000},
        {3, 9_000},
        {4, 16_000},
        {5, 25_000},
        {6, 36_000},
        {7, 49_000},
        {8, 64_000},
        {9, 81_000},
        {10, 100_000}
      ]

      Enum.reduce(expectations, failure_context, fn {expected_failures, expected_delay}, ctx ->
        {:retry, actual_delay, context} =
          ErrorHandler.backoff(an_error(), an_event(), ctx, no_jitter())

        assert actual_delay == expected_delay
        actual_failures = Map.fetch!(context.context, :failures)
        assert actual_failures == expected_failures

        context
      end)
    end

    test "maxes out at 1 day" do
      # We should hit the max after 294 failures
      context = %FailureContext{context: %{failures: 500}}

      {:retry, actual_delay, _context} =
        ErrorHandler.backoff(an_error(), an_event(), context, no_jitter())

      assert actual_delay == :timer.hours(24)
    end
  end

  defp an_event, do: %Event{id: 123}
  defp an_error, do: {:error, "Invalid pizza toppings"}
  defp no_jitter, do: fn -> 0 end
  defp failure_context, do: %FailureContext{context: %{}}
end
