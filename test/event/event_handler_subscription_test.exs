defmodule Commanded.Event.EventHandlerSubscriptionTest do
  use Commanded.MockEventStoreCase

  alias Commanded.Event.Handler

  defmodule ExampleHandler do
    use Commanded.Event.Handler,
      application: Commanded.MockedApp,
      name: "ExampleHandler"
  end

  describe "event handler subscription" do
    setup [:verify_on_exit!]

    test "should monitor subscription and terminate handler on shutdown" do
      {:ok, subscription} = start_subscription()

      expect_subscribe_to(subscription)

      {:ok, handler} = start_handler(subscription)

      Process.unlink(handler)
      ref = Process.monitor(handler)

      shutdown_subscription(subscription)

      assert_receive {:DOWN, ^ref, :process, ^handler, _reason}
    end

    test "should retry subscription on error" do
      {:ok, subscription} = start_subscription()

      reply_to = self()

      # First and second subscription attempts fail
      expect(MockEventStore, :subscribe_to, 2, fn
        _event_store_meta, :all, "ExampleHandler", handler, :origin, _opts ->
          send(reply_to, {:subscribe_to, handler})

          {:error, :subscription_already_exists}
      end)

      # Third subscription attempt succeeds
      expect_subscribe_to(subscription)

      {:ok, handler} = ExampleHandler.start_link()

      assert_receive {:subscribe_to, ^handler}
      assert_handler_subscription_timer(handler, 1..3_000)
      refute_receive {:subscribed, ^subscription}

      send(handler, :subscribe_to_events)

      assert_receive {:subscribe_to, ^handler}
      assert_handler_subscription_timer(handler, 1_000..9_000)
      refute_receive {:subscribed, ^subscription}

      send(handler, :subscribe_to_events)

      assert_receive {:subscribed, ^subscription}
    end
  end

  defp assert_handler_subscription_timer(handler, expected_timer_range) do
    %Handler{subscribe_timer: subscribe_timer} = :sys.get_state(handler)

    assert is_reference(subscribe_timer)

    timer = Process.read_timer(subscribe_timer)

    assert is_integer(timer)
    assert timer in expected_timer_range
  end

  defp start_subscription do
    pid =
      spawn_link(fn ->
        receive do
          :shutdown -> :ok
        end
      end)

    {:ok, pid}
  end

  defp expect_subscribe_to(subscription) do
    reply_to = self()

    expect(MockEventStore, :subscribe_to, fn
      _event_store_meta, :all, "ExampleHandler", handler, :origin, _opts ->
        send(handler, {:subscribed, subscription})
        send(reply_to, {:subscribed, subscription})

        {:ok, subscription}
    end)
  end

  defp start_handler(subscription) do
    {:ok, pid} = ExampleHandler.start_link()

    assert_receive {:subscribed, ^subscription}

    {:ok, pid}
  end

  defp shutdown_subscription(subscription) do
    ref = Process.monitor(subscription)

    send(subscription, :shutdown)

    assert_receive {:DOWN, ^ref, :process, ^subscription, _reason}
  end
end
