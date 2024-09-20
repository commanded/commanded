defmodule Commanded.Event.HandlerAfterStartTest do
  use Commanded.MockEventStoreCase

  import Mox

  alias Commanded.Event.AfterStartHandler
  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore

  describe "event handler `after_start/1` callback" do
    setup do
      true = Process.register(self(), :test)

      expect(MockEventStore, :subscribe_to, fn
        _event_store, :all, handler_name, handler, _subscribe_from, _opts ->
          assert is_binary(handler_name)

          {:ok, handler}
      end)

      handler = start_supervised!(AfterStartHandler)

      [handler: handler]
    end

    test "should be called after subscription subscribed", %{handler: handler} do
      refute_receive {:after_start, ^handler}

      send_subscribed(handler)

      assert_receive {:after_start, ^handler}
    end
  end

  defp send_subscribed(handler) do
    send(handler, {:subscribed, handler})
  end
end
