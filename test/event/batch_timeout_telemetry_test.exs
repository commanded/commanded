defmodule Commanded.Event.BatchTimeoutTelemetryTest do
  @moduledoc """
  Tests for batch timeout telemetry events.

  Verifies that flush_reason is correctly included in telemetry metadata.
  """

  use ExUnit.Case, async: false

  alias Commanded.Application.Config
  alias Commanded.Event.Handler
  alias Commanded.EventStore.Subscription
  alias Commanded.Helpers.EventFactory

  setup do
    # Configure mock adapter
    Config.associate(self(), __MODULE__, event_store: {__MODULE__.MockAdapter, nil})

    # Attach telemetry handler
    ref = :telemetry_test.attach_event_handlers(self(), [[:commanded, :event, :batch, :stop]])

    on_exit(fn ->
      :telemetry.detach(ref)
    end)

    :ok
  end

  defmodule TrackEvent do
    @derive Jason.Encoder
    defstruct [:id]
  end

  defmodule TelemetryHandler do
    use Commanded.Event.Handler,
      application: Commanded.DefaultApp,
      name: __MODULE__,
      batch_size: 10,
      batch_timeout: 100

    def handle_batch(_events) do
      :ok
    end
  end

  describe "flush_reason telemetry" do
    test "emits :size flush_reason when batch fills" do
      state = setup_state(TelemetryHandler, batch_size: 3, batch_timeout: 1000)

      # Send exactly batch_size events
      events = build_events(3)
      recorded_events = EventFactory.map_to_recorded_events(events, 1)

      {:noreply, _state} = Handler.handle_info({:events, recorded_events}, state)

      # Wait for telemetry event
      assert_receive {[:commanded, :event, :batch, :stop], _ref, _measurements, metadata}, 200

      # Verify flush_reason is :size
      assert metadata.flush_reason == :size
      assert metadata.event_count == 3
    end

    test "emits :timeout flush_reason when timeout triggers" do
      state = setup_state(TelemetryHandler, batch_size: 10, batch_timeout: 100)

      # Send partial batch
      events = build_events(3)
      recorded_events = EventFactory.map_to_recorded_events(events, 1)

      {:noreply, state1} = Handler.handle_info({:events, recorded_events}, state)

      # Wait for timeout and process it
      assert_receive :flush_batch_timeout, 200
      {:noreply, _state2} = Handler.handle_info(:flush_batch_timeout, state1)

      # Wait for telemetry event
      assert_receive {[:commanded, :event, :batch, :stop], _ref, _measurements, metadata}, 200

      # Verify flush_reason is :timeout
      assert metadata.flush_reason == :timeout
      assert metadata.event_count == 3
    end

    test "emits :immediate flush_reason when no timeout configured" do
      state = setup_state(TelemetryHandler, batch_size: 10, batch_timeout: :infinity)

      # Send events
      events = build_events(3)
      recorded_events = EventFactory.map_to_recorded_events(events, 1)

      {:noreply, _state} = Handler.handle_info({:events, recorded_events}, state)

      # Wait for telemetry event
      assert_receive {[:commanded, :event, :batch, :stop], _ref, _measurements, metadata}, 200

      # Verify flush_reason is :immediate
      assert metadata.flush_reason == :immediate
      assert metadata.event_count == 3
    end

    test "includes duration measurement" do
      state = setup_state(TelemetryHandler, batch_size: 3, batch_timeout: 100)

      events = build_events(3)
      recorded_events = EventFactory.map_to_recorded_events(events, 1)

      {:noreply, _state} = Handler.handle_info({:events, recorded_events}, state)

      # Wait for telemetry event
      assert_receive {[:commanded, :event, :batch, :stop], _ref, measurements, metadata}, 200

      # Verify measurements include duration
      assert is_integer(measurements.duration)
      assert measurements.duration > 0

      # Verify complete metadata
      assert metadata.flush_reason == :size
      assert metadata.event_count == 3
      assert metadata.handler_name
      assert metadata.first_event_id
      assert metadata.last_event_id
    end
  end

  describe "telemetry for monitoring" do
    test "can track flush reason distribution" do
      state = setup_state(TelemetryHandler, batch_size: 5, batch_timeout: 100)

      # Size flush
      events1 = build_events(5)
      recorded1 = EventFactory.map_to_recorded_events(events1, 1)
      {:noreply, state1} = Handler.handle_info({:events, recorded1}, state)

      assert_receive {[:commanded, :event, :batch, :stop], _ref, _m1, metadata1}, 200
      assert metadata1.flush_reason == :size

      # Timeout flush
      events2 = build_events(2)
      recorded2 = EventFactory.map_to_recorded_events(events2, 6)
      {:noreply, state2} = Handler.handle_info({:events, recorded2}, state1)

      assert_receive :flush_batch_timeout, 200
      {:noreply, _state3} = Handler.handle_info(:flush_batch_timeout, state2)

      assert_receive {[:commanded, :event, :batch, :stop], _ref, _m2, metadata2}, 200
      assert metadata2.flush_reason == :timeout

      # Can aggregate these metrics to see:
      # - How many size vs timeout flushes
      # - Average batch size by flush reason
      # - Processing duration by flush reason
    end
  end

  # Helper functions

  defp setup_state(handler_module, opts) do
    batch_size = Keyword.fetch!(opts, :batch_size)
    batch_timeout = Keyword.fetch!(opts, :batch_timeout)

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
      %TrackEvent{id: n}
    end
  end

  defmodule MockAdapter do
    @moduledoc false

    def ack_event(nil, subscription_pid, event) do
      send(subscription_pid, {:acked, event})
      :ok
    end
  end
end
