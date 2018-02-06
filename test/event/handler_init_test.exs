defmodule Commanded.Event.HandlerInitTest do
  use Commanded.StorageCase

  import Mox

  alias Commanded.Event.InitHandler
  alias Commanded.Helpers.ProcessHelper
  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore

  setup do
    reply_to = self()
    {:ok, agent} = Agent.start_link(fn -> reply_to end, name: {:global, InitHandler})

    on_exit(fn ->
      ProcessHelper.shutdown(agent)
    end)
  end

  describe "event handler `init/0` callback" do
    setup do
      {:ok, handler} = InitHandler.start_link()

      on_exit(fn ->
        ProcessHelper.shutdown(handler)
      end)

      [handler: handler]
    end

    test "should be called", %{handler: handler} do
      assert_receive {:init, ^handler}
    end
  end

  describe "event handler `init/0` callback after subscribed" do
    setup do
      set_mox_global()

      # use mock event store adapter
      default_event_store_adapter = Application.get_env(:commanded, :event_store_adapter)
      :ok = Application.put_env(:commanded, :event_store_adapter, MockEventStore)

      expect(MockEventStore, :subscribe_to_all_streams, fn _handler_name, handler, _subscribe_from ->
        {:ok, handler}
      end)

      {:ok, handler} = InitHandler.start_link()

      on_exit(fn ->
        Application.put_env(:commanded, :event_store_adapter, default_event_store_adapter)
        ProcessHelper.shutdown(handler)
      end)

      [handler: handler]
    end

    test "should be called after subscription subscribed", %{handler: handler} do
      refute_receive {:init, ^handler}

      simulate_subscribed(handler)

      assert_receive {:init, ^handler}
    end

    defp simulate_subscribed(handler) do
      send(handler, {:subscribed, handler})
    end
  end
end
