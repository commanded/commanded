defmodule Commanded.Event.HandlerInitTest do
  use Commanded.MockEventStoreCase

  import Mox

  alias Commanded.Event.InitHandler
  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore

  setup do
    reply_to = self()

    expect(MockEventStore, :subscribe_to, fn :all, _handler_name, handler, _subscribe_from ->
      {:ok, handler}
    end)

    {:ok, agent} = Agent.start_link(fn -> reply_to end, name: InitHandler)
    {:ok, handler} = InitHandler.start_link()

    [agent: agent, handler: handler]
  end

  describe "event handler `init/0` callback" do
    test "should be called", %{handler: handler} do
      send_subscribed(handler)

      assert_receive {:init, ^handler}
    end
  end

  describe "event handler `init/0` callback after subscribed" do
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
