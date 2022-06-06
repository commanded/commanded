defmodule Commanded.ProcessManagers.ProcessManagerSubscriptionTest do
  use Commanded.MockEventStoreCase

  alias Commanded.MockedApp
  alias Commanded.ProcessManagers.ProcessRouter

  defmodule ExampleProcessManager do
    use Commanded.ProcessManagers.ProcessManager,
      application: MockedApp,
      name: "ExampleProcessManager"

    @derive Jason.Encoder
    defstruct [:data]
  end

  describe "process manager subscription" do
    test "should monitor subscription and terminate process manager on shutdown" do
      {:ok, subscription} = start_subscription()

      expect_subscribe_to(subscription)

      {:ok, pm} = start_process_manager(subscription)

      Process.unlink(pm)
      ref = Process.monitor(pm)

      shutdown_subscription(subscription)

      assert_receive {:DOWN, ^ref, :process, ^pm, _reason}
    end
  end

  test "should retry subscription on error" do
    {:ok, subscription} = start_subscription()

    reply_to = self()

    # First and second subscription attempts fail
    expect(MockEventStore, :subscribe_to, 2, fn
      _event_store_meta, :all, "ExampleProcessManager", pm, :origin, _opts ->
        send(reply_to, {:subscribe_to, pm})

        {:error, :subscription_already_exists}
    end)

    # Third subscription attempt succeeds
    expect_subscribe_to(subscription)

    {:ok, pm} = ExampleProcessManager.start_link()

    assert_receive {:subscribe_to, ^pm}
    assert_subscription_timer(pm, 1..3_000)
    refute_receive {:subscribed, ^subscription}

    send(pm, :subscribe_to_events)

    assert_receive {:subscribe_to, ^pm}
    assert_subscription_timer(pm, 1_000..9_000)
    refute_receive {:subscribed, ^subscription}

    send(pm, :subscribe_to_events)

    assert_receive {:subscribed, ^subscription}
  end

  defp assert_subscription_timer(pm, expected_timer_range) do
    %ProcessRouter.State{subscribe_timer: subscribe_timer} = :sys.get_state(pm)

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
      _event_store_meta, :all, "ExampleProcessManager", pm, :origin, _opts ->
        send(pm, {:subscribed, subscription})
        send(reply_to, {:subscribed, subscription})

        {:ok, subscription}
    end)
  end

  defp start_process_manager(subscription) do
    {:ok, pid} = ExampleProcessManager.start_link()

    assert_receive {:subscribed, ^subscription}

    {:ok, pid}
  end

  defp shutdown_subscription(subscription) do
    ref = Process.monitor(subscription)

    send(subscription, :shutdown)

    assert_receive {:DOWN, ^ref, :process, _, _}
  end
end
