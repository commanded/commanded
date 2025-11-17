defmodule Commanded.Event.BatchTimeoutTest do
  @moduledoc """
  Tests for batch timeout functionality.

  Verifies that batches flush based on time OR size, whichever comes first.
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

  # Test module for validation tests
  defmodule TestModule do
    def init(config), do: {:ok, config}
  end

  defmodule ReplyEvent do
    @derive Jason.Encoder
    defstruct [:reply_to, :value]
  end

  defmodule BatchTimeoutHandler do
    use Commanded.Event.Handler,
      application: Commanded.DefaultApp,
      name: __MODULE__,
      batch_size: 5,
      batch_timeout: 100

    def handle_batch(events) do
      # Extract reply_to from first event's data
      [{event_data, _metadata} | _] = events
      reply_to = Map.get(event_data, :reply_to)

      if reply_to do
        send(reply_to, {:batch_processed, length(events)})
      end

      :ok
    end
  end

  describe "batch timeout configuration" do
    test "accepts valid timeout values" do
      # Valid: positive integer
      state = setup_state(BatchTimeoutHandler, batch_timeout: 100)
      assert state.batch_timeout == 100

      # Valid: :infinity
      state = setup_state(BatchTimeoutHandler, batch_timeout: :infinity)
      assert state.batch_timeout == :infinity
    end

    test "rejects invalid batch_size values" do
      assert_raise ArgumentError, ~r/:batch_size must be nil or positive integer/, fn ->
        Handler.parse_config!(__MODULE__.TestModule,
          application: Commanded.DefaultApp,
          name: "TestHandler",
          batch_size: -10
        )
      end

      assert_raise ArgumentError, ~r/:batch_size must be nil or positive integer/, fn ->
        Handler.parse_config!(__MODULE__.TestModule,
          application: Commanded.DefaultApp,
          name: "TestHandler",
          batch_size: 0
        )
      end
    end

    test "rejects invalid batch_timeout values" do
      assert_raise ArgumentError, ~r/:batch_timeout must be :infinity or positive integer/, fn ->
        Handler.parse_config!(__MODULE__.TestModule,
          application: Commanded.DefaultApp,
          name: "TestHandler",
          batch_size: 10,
          batch_timeout: -100
        )
      end

      assert_raise ArgumentError, ~r/:batch_timeout must be :infinity or positive integer/, fn ->
        Handler.parse_config!(__MODULE__.TestModule,
          application: Commanded.DefaultApp,
          name: "TestHandler",
          batch_size: 10,
          batch_timeout: 0
        )
      end
    end

    test "requires batch_size when batch_timeout is provided" do
      assert_raise ArgumentError, ~r/:batch_timeout requires :batch_size/, fn ->
        Handler.parse_config!(__MODULE__.TestModule,
          application: Commanded.DefaultApp,
          name: "TestHandler",
          batch_timeout: 100
        )
      end
    end
  end

  describe "batch flushing" do
    test "flushes on size threshold before timeout" do
      state = setup_state(BatchTimeoutHandler, batch_size: 3, batch_timeout: 1000)

      # Send 3 events (exactly batch_size)
      events = build_events(3, reply_to: self())
      recorded_events = EventFactory.map_to_recorded_events(events, 1)

      {:noreply, new_state} = Handler.handle_info({:events, recorded_events}, state)

      # Should flush immediately on size, not wait for timeout
      assert_receive {:batch_processed, 3}, 50

      # Buffer should be empty
      assert new_state.batch_buffer == []
      # Timer should be nil (cancelled)
      assert new_state.batch_timer_ref == nil
    end

    test "flushes on timeout with partial batch" do
      state = setup_state(BatchTimeoutHandler, batch_size: 10, batch_timeout: 100)

      # Send 3 events (less than batch_size)
      events = build_events(3, reply_to: self())
      recorded_events = EventFactory.map_to_recorded_events(events, 1)

      {:noreply, new_state} = Handler.handle_info({:events, recorded_events}, state)

      # Should NOT flush immediately
      refute_receive {:batch_processed, _}, 50

      # Buffer should have 3 events
      assert length(new_state.batch_buffer) == 3

      # Timer should be set
      assert is_reference(new_state.batch_timer_ref)

      # Wait for timeout message, then manually process it
      assert_receive :flush_batch_timeout, 200
      {:noreply, _final_state} = Handler.handle_info(:flush_batch_timeout, new_state)

      # Batch should now be processed
      assert_receive {:batch_processed, 3}, 50
    end

    test "accumulates events arriving within timeout window" do
      state = setup_state(BatchTimeoutHandler, batch_size: 20, batch_timeout: 150)

      # Send 3 events
      events1 = build_events(3, reply_to: self())
      recorded1 = EventFactory.map_to_recorded_events(events1, 1)
      {:noreply, state1} = Handler.handle_info({:events, recorded1}, state)

      # Wait a bit, send 2 more (still within timeout window)
      Process.sleep(50)
      events2 = build_events(2, reply_to: self())
      recorded2 = EventFactory.map_to_recorded_events(events2, 4)
      {:noreply, state2} = Handler.handle_info({:events, recorded2}, state1)

      # Buffer should have 5 events
      assert length(state2.batch_buffer) == 5

      # Wait for timeout message, then manually process it
      assert_receive :flush_batch_timeout, 200
      {:noreply, _final_state} = Handler.handle_info(:flush_batch_timeout, state2)

      # Should flush all 5 events together
      assert_receive {:batch_processed, 5}, 50
    end
  end

  describe "backwards compatibility" do
    test "no timeout (:infinity) processes immediately" do
      state = setup_state(BatchTimeoutHandler, batch_size: 10, batch_timeout: :infinity)

      # Send partial batch
      events = build_events(5, reply_to: self())
      recorded_events = EventFactory.map_to_recorded_events(events, 1)

      {:noreply, new_state} = Handler.handle_info({:events, recorded_events}, state)

      # Should flush immediately (EventStore subscription handles batching)
      assert_receive {:batch_processed, 5}, 50

      # Buffer should be empty
      assert new_state.batch_buffer == [] or is_nil(new_state.batch_buffer)

      # No timer should be set
      assert new_state.batch_timer_ref == nil
    end
  end

  # Helper functions
  defp setup_state(handler_module, opts) do
    batch_size = Keyword.get(opts, :batch_size, 5)
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

  defp build_events(count, opts) do
    reply_to = Keyword.get(opts, :reply_to)

    for n <- 1..count do
      %ReplyEvent{
        reply_to: reply_to,
        value: n
      }
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
