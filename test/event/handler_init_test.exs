defmodule Commanded.Event.HandlerInitTest do
  use Commanded.MockEventStoreCase

  import Mox

  alias Commanded.DefaultApp
  alias Commanded.Event.{InitHandler, RuntimeConfigHandler}
  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore

  describe "event handler `init/1` callback" do
    setup do
      for tenant <- [:tenant1, :tenant2, :tenant3] do
        start_supervised!({DefaultApp, name: Module.concat([DefaultApp, tenant])})
      end

      :ok
    end

    test "should be called at runtime" do
      {:ok, _handler1} = RuntimeConfigHandler.start_link(tenant: :tenant1, reply_to: self())
      {:ok, _handler2} = RuntimeConfigHandler.start_link(tenant: :tenant2, reply_to: self())
      {:ok, _handler3} = RuntimeConfigHandler.start_link(tenant: :tenant3, reply_to: self())

      assert_receive {:init, :tenant1}
      assert_receive {:init, :tenant2}
      assert_receive {:init, :tenant3}
    end
  end

  describe "event handler `init/0` callback" do
    setup do
      reply_to = self()

      subscribe_to = fn _event_store, :all, handler_name, handler, _subscribe_from ->
        assert is_binary(handler_name)

        {:ok, handler}
      end

      expect(MockEventStore, :subscribe_to, subscribe_to)

      {:ok, _agent} = Agent.start_link(fn -> reply_to end, name: InitHandler)

      handler = start_supervised!(InitHandler)

      [handler: handler]
    end

    test "should be called after subscription subscribed", %{handler: handler} do
      refute_receive {:init, ^handler}

      send_subscribed(handler)

      assert_receive {:init, ^handler}
    end

    defp send_subscribed(handler) do
      send(handler, {:subscribed, handler})
    end
  end
end
