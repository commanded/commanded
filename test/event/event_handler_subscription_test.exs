defmodule Commanded.Event.EventHandlerSubscriptionTest do
  use Commanded.MockEventStoreCase

  defmodule ExampleHandler do
    use Commanded.Event.Handler,
      application: Commanded.MockedApp,
      name: "ExampleHandler"
  end

  setup do
    {:ok, subscription} = start_subscription()
    {:ok, handler} = start_handler(subscription)

    [
      handler: handler,
      subscription: subscription
    ]
  end

  describe "event handler subscription" do
    test "should monitor subscription and terminate handler on shutdown", %{
      handler: handler,
      subscription: subscription
    } do
      Process.unlink(handler)
      ref = Process.monitor(handler)

      shutdown_subscription(subscription)

      assert_receive {:DOWN, ^ref, :process, ^handler, :normal}
    end
  end

  defp start_subscription do
    pid =
      spawn(fn ->
        receive do
          :shutdown -> :ok
        end
      end)

    {:ok, pid}
  end

  defp start_handler(subscription) do
    reply_to = self()

    expect(MockEventStore, :subscribe_to, fn _event_store,
                                             :all,
                                             "ExampleHandler",
                                             handler,
                                             :origin ->
      send(handler, {:subscribed, subscription})
      send(reply_to, {:subscribed, subscription})

      {:ok, subscription}
    end)

    {:ok, pid} = ExampleHandler.start_link()

    assert_receive {:subscribed, ^subscription}

    {:ok, pid}
  end

  defp shutdown_subscription(subscription) do
    ref = Process.monitor(subscription)

    send(subscription, :shutdown)

    assert_receive {:DOWN, ^ref, :process, _, _}
  end
end
