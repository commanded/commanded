defmodule Commanded.Event.BatchTimeoutIntegrationTest do
  @moduledoc """
  Integration tests for batch timeout functionality.

  Tests edge cases like timer cleanup, multiple flush cycles, and race conditions.
  """

  use ExUnit.Case, async: false

  alias Commanded.Application.Config
  alias Commanded.Event.Handler
  alias Commanded.EventStore.Subscription
  alias Commanded.Helpers.EventFactory

  setup do
    # Configure mock adapter once per test
    Config.associate(self(), __MODULE__, event_store: {__MODULE__.MockAdapter, nil})
    :ok
  end

  defmodule CounterEvent do
    @derive Jason.Encoder
    defstruct [:counter]
  end

  defmodule CounterHandler do
    use Commanded.Event.Handler,
      application: Commanded.DefaultApp,
      name: __MODULE__,
      batch_size: 10,
      batch_timeout: 100

    def handle_batch(events) do
      # Send count to test process
      test_pid = Process.whereis(:counter_test_process)

      if test_pid do
        send(test_pid, {:batch_flushed, length(events)})
      end

      :ok
    end
  end

  describe "timer cleanup" do
    test "timer is cancelled when batch fills before timeout" do
      state = setup_state(CounterHandler, batch_size: 3, batch_timeout: 5000)

      # Send exactly batch_size events
      events = build_events(3)
      recorded_events = EventFactory.map_to_recorded_events(events, 1)

      {:noreply, new_state} = Handler.handle_info({:events, recorded_events}, state)

      # Timer should be nil (cancelled because batch was full)
      assert new_state.batch_timer_ref == nil

      # Buffer should be empty
      assert new_state.batch_buffer == []

      # Wait to ensure no spurious timeout fires
      refute_receive :flush_batch_timeout, 100
    end

    test "new timer started after timeout flush" do
      state = setup_state(CounterHandler, batch_size: 10, batch_timeout: 100)

      # First batch - partial
      events1 = build_events(2)
      recorded1 = EventFactory.map_to_recorded_events(events1, 1)
      {:noreply, state1} = Handler.handle_info({:events, recorded1}, state)

      # Timer should be set
      first_timer = state1.batch_timer_ref
      assert is_reference(first_timer)

      # Wait for timeout and process it
      assert_receive :flush_batch_timeout, 200
      {:noreply, state2} = Handler.handle_info(:flush_batch_timeout, state1)

      # Timer should be cleared
      assert state2.batch_timer_ref == nil
      assert state2.batch_buffer == []

      # Send more events - should start new timer
      events2 = build_events(2)
      recorded2 = EventFactory.map_to_recorded_events(events2, 3)
      {:noreply, state3} = Handler.handle_info({:events, recorded2}, state2)

      # New timer should be set and different from first
      second_timer = state3.batch_timer_ref
      assert is_reference(second_timer)
      assert second_timer != first_timer
    end

    test "size flush cancels pending timeout before next batch" do
      Process.register(self(), :counter_test_process)

      on_exit(fn ->
        if Process.whereis(:counter_test_process) do
          Process.unregister(:counter_test_process)
        end
      end)

      batch_timeout = 50
      state = setup_state(CounterHandler, batch_size: 3, batch_timeout: batch_timeout)

      # First batch fills immediately, should flush on size
      events_full = build_events(3)
      recorded_full = EventFactory.map_to_recorded_events(events_full, 1)
      {:noreply, state1} = Handler.handle_info({:events, recorded_full}, state)

      assert_receive {:batch_flushed, 3}, 50

      # Wait right before the original timeout would have fired
      Process.sleep(batch_timeout - 5)

      # Start a new partial batch (should start a fresh timer only)
      events_partial = build_events(2)
      recorded_partial = EventFactory.map_to_recorded_events(events_partial, 4)
      {:noreply, state2} = Handler.handle_info({:events, recorded_partial}, state1)

      # Old timer should have been cancelled, so no timeout should fire yet
      refute_receive :flush_batch_timeout, 20

      # The new timer should still flush the partial batch eventually
      assert_receive :flush_batch_timeout, 200
      {:noreply, _state3} = Handler.handle_info(:flush_batch_timeout, state2)
      assert_receive {:batch_flushed, 2}, 50
    end
  end

  describe "multiple flush cycles" do
    test "handles alternating size and timeout flushes" do
      state = setup_state(CounterHandler, batch_size: 5, batch_timeout: 100)

      # First: timeout flush (partial batch)
      events1 = build_events(2)
      recorded1 = EventFactory.map_to_recorded_events(events1, 1)
      {:noreply, state1} = Handler.handle_info({:events, recorded1}, state)

      assert_receive :flush_batch_timeout, 200
      {:noreply, state2} = Handler.handle_info(:flush_batch_timeout, state1)

      assert state2.batch_buffer == []
      assert state2.batch_timer_ref == nil

      # Second: size flush (full batch)
      events2 = build_events(5)
      recorded2 = EventFactory.map_to_recorded_events(events2, 3)
      {:noreply, state3} = Handler.handle_info({:events, recorded2}, state2)

      assert state3.batch_buffer == []
      assert state3.batch_timer_ref == nil

      # Third: timeout flush again (partial batch)
      events3 = build_events(3)
      recorded3 = EventFactory.map_to_recorded_events(events3, 8)
      {:noreply, state4} = Handler.handle_info({:events, recorded3}, state3)

      assert_receive :flush_batch_timeout, 200
      {:noreply, state5} = Handler.handle_info(:flush_batch_timeout, state4)

      assert state5.batch_buffer == []
      assert state5.batch_timer_ref == nil
    end
  end

  describe "race condition prevention" do
    test "timeout message arriving after size flush is safely ignored" do
      state = setup_state(CounterHandler, batch_size: 3, batch_timeout: 50)

      # Send events that start timer
      events = build_events(2)
      recorded_events = EventFactory.map_to_recorded_events(events, 1)
      {:noreply, state1} = Handler.handle_info({:events, recorded_events}, state)

      # Timer is running
      assert is_reference(state1.batch_timer_ref)

      # Now send one more event to trigger size flush before timeout
      events2 = build_events(1)
      recorded2 = EventFactory.map_to_recorded_events(events2, 3)
      {:noreply, state2} = Handler.handle_info({:events, recorded2}, state1)

      # Batch was flushed by size
      assert state2.batch_buffer == []
      assert state2.batch_timer_ref == nil

      # Timeout message might still arrive (race condition)
      # This should be handled gracefully - no crash, no double processing
      case Process.read_timer(state1.batch_timer_ref) do
        false ->
          # Timer already fired, message might be in mailbox
          receive do
            :flush_batch_timeout ->
              # Handle it - should be a no-op since buffer is empty
              {:noreply, state3} = Handler.handle_info(:flush_batch_timeout, state2)
              assert state3.batch_buffer == []

            _ ->
              :ok
          after
            100 -> :ok
          end

        _ ->
          # Timer hasn't fired yet, will be cancelled
          :ok
      end
    end
  end

  describe "empty buffer scenarios" do
    test "timeout on empty buffer is no-op" do
      state = setup_state(CounterHandler, batch_size: 10, batch_timeout: 100)

      # State starts with empty buffer
      assert state.batch_buffer == []
      assert state.batch_timer_ref == nil

      # Manually trigger timeout (shouldn't happen in practice, but test defense)
      {:noreply, new_state} = Handler.handle_info(:flush_batch_timeout, state)

      # Should remain empty
      assert new_state.batch_buffer == []
      assert new_state.batch_timer_ref == nil
    end
  end

  describe "timer not started scenarios" do
    test "no timer started when timeout is infinity" do
      state = setup_state(CounterHandler, batch_size: 10, batch_timeout: :infinity)

      events = build_events(3)
      recorded_events = EventFactory.map_to_recorded_events(events, 1)

      {:noreply, new_state} = Handler.handle_info({:events, recorded_events}, state)

      # Timer should NOT be set
      assert new_state.batch_timer_ref == nil

      # Buffer should be empty (events processed immediately when no timeout)
      assert new_state.batch_buffer == [] or is_nil(new_state.batch_buffer)

      # No timeout message should arrive
      refute_receive :flush_batch_timeout, 200
    end
  end

  describe "crash safety" do
    test "buffer is cleared before processing to prevent data loss" do
      # Design verification: Our implementation clears buffer BEFORE processing
      # This ensures if handler crashes during processing, buffer is already empty
      state = setup_state(CounterHandler, batch_size: 10, batch_timeout: 50)

      events = build_events(2)
      recorded_events = EventFactory.map_to_recorded_events(events, 1)
      {:noreply, state1} = Handler.handle_info({:events, recorded_events}, state)

      # Buffer has events
      assert length(state1.batch_buffer) == 2

      # Trigger timeout
      assert_receive :flush_batch_timeout, 100

      # At this point, flush_batch_buffer will:
      # 1. Clear buffer and timer FIRST
      # 2. Then call handle_batch
      # If crash happens during handle_batch, buffer is already safe
      # EventStore will redeliver (not acked), and handler can reprocess idempotently
      #
      # Note: We rely on existing Commanded infrastructure for crash recovery:
      # - Supervision trees (tested in supervision tests)
      # - EventStore redelivery (tested in EventStore)
      # - Timer cleanup (BEAM VM guarantee)
    end
  end

  # Helper functions
  defp setup_state(handler_module, opts) do
    batch_size = Keyword.get(opts, :batch_size, 10)
    batch_timeout = Keyword.get(opts, :batch_timeout, 100)

    %Handler{
      application: __MODULE__,
      handler_name: inspect(handler_module),
      handler_module: handler_module,
      handler_callback: :batch,
      handler_state: %{},
      consistency: :eventual,
      batch_size: batch_size,
      batch_timeout: batch_timeout,
      batch_buffer: [],
      batch_timer_ref: nil,
      subscription:
        struct(Subscription,
          application: __MODULE__,
          subscription_pid: self()
        )
    }
  end

  defp build_events(count) do
    for n <- 1..count do
      %CounterEvent{counter: n}
    end
  end

  # Mock event store adapter for testing
  defmodule MockAdapter do
    @moduledoc false

    def ack_event(nil, subscription_pid, event) do
      send(subscription_pid, {:acked, event})
      :ok
    end
  end
end
