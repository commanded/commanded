defmodule Commanded.ProcessManagers.ProcessManagerSubscriptionTest do
  use Commanded.MockEventStoreCase

  alias Commanded.MockedApp

  defmodule ExampleProcessManager do
    use Commanded.ProcessManagers.ProcessManager,
      application: MockedApp,
      name: "ExampleProcessManager"

    @derive Jason.Encoder
    defstruct [:data]
  end

  setup do
    {:ok, subscription} = start_subscription()
    {:ok, pm} = start_process_manager(subscription)

    [
      pm: pm,
      subscription: subscription
    ]
  end

  describe "process manager subscription" do
    test "should monitor subscription and terminate process manager on shutdown", %{
      pm: pm,
      subscription: subscription
    } do
      Process.unlink(pm)
      ref = Process.monitor(pm)

      shutdown_subscription(subscription)

      assert_receive {:DOWN, ^ref, :process, ^pm, :normal}
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

  defp start_process_manager(subscription) do
    reply_to = self()

    expect(MockEventStore, :subscribe_to, fn _event_store,
                                             :all,
                                             {Commanded.MockedApp,
                                              Commanded.ProcessManagers.ProcessRouter,
                                              "ExampleProcessManager"},
                                             pm,
                                             :origin ->
      send(pm, {:subscribed, subscription})
      send(reply_to, {:subscribed, subscription})

      {:ok, subscription}
    end)

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
