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
        ErrorHandler.backoff(an_error(), an_event(), context, jitter_fn: no_jitter())

      assert context.context.failures == 1
      assert delay == :timer.seconds(1)
    end

    test "applies jitter to delay" do
      jitter_fn = fn -> 234 end

      {:retry, delay, _} =
        ErrorHandler.backoff(an_error(), an_event(), failure_context(), jitter_fn: jitter_fn)

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
          ErrorHandler.backoff(an_error(), an_event(), ctx, jitter_fn: no_jitter())

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
        ErrorHandler.backoff(an_error(), an_event(), context, jitter_fn: no_jitter())

      assert actual_delay == :timer.hours(24)
    end

    test "retains failure_context" do
      failure_context = %FailureContext{
        application: MyApp.CommandedApp,
        handler_name: "MyApp.FailingEventHandler",
        handler_state: nil,
        context: %{},
        metadata: %{
          application: MyApp.CommandedApp,
          causation_id: "49d9a83c-8bcd-4fa9-9ccb-3c196717415c",
          correlation_id: "e9c3b49e-0ac5-44db-8ddb-83835a7c9437",
          created_at: ~U[2024-06-25 20:55:24.576545Z],
          event_id: "0f117f39-3b2f-491e-b39d-9325fd1d19d1",
          event_number: 1,
          handler_name: "MyApp.FailingEventHandler",
          state: nil,
          stream_id: "2iO5kHYbIAGW1rrZ7FeHCRMvbT5",
          stream_version: 1
        },
        stacktrace: nil
      }

      assert {:retry, _delay, ctx} = ErrorHandler.backoff(an_error(), an_event(), failure_context)

      assert ctx == %FailureContext{
               application: MyApp.CommandedApp,
               handler_name: "MyApp.FailingEventHandler",
               handler_state: nil,
               context: %{failures: 1},
               metadata: %{
                 application: MyApp.CommandedApp,
                 causation_id: "49d9a83c-8bcd-4fa9-9ccb-3c196717415c",
                 correlation_id: "e9c3b49e-0ac5-44db-8ddb-83835a7c9437",
                 created_at: ~U[2024-06-25 20:55:24.576545Z],
                 event_id: "0f117f39-3b2f-491e-b39d-9325fd1d19d1",
                 event_number: 1,
                 handler_name: "MyApp.FailingEventHandler",
                 state: nil,
                 stream_id: "2iO5kHYbIAGW1rrZ7FeHCRMvbT5",
                 stream_version: 1
               },
               stacktrace: nil
             }
    end
  end

  defp an_event, do: %Event{id: 123}
  defp an_error, do: {:error, "Invalid pizza toppings"}
  defp no_jitter, do: fn -> 0 end
  defp failure_context, do: %FailureContext{context: %{}}
end
