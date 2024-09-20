defmodule Commanded.Event.HandlerAfterStartTest do
  use Commanded.MockEventStoreCase

  import Mox
  import ExUnit.CaptureLog

  alias Commanded.EventStore.Adapters.Mock, as: MockEventStore

  setup do
    stub(MockEventStore, :subscribe_to, fn
      _event_store, :all, _handler_name, handler, _subscribe_from, _opts ->
        {:ok, handler}
    end)

    :ok
  end

  describe "event handler `init/0` callback" do
    # TODO: remove these test when we remove init/0

    setup(%{test: test}) do
      # HACK: generate a module that can communicate back to our test process
      true = Process.register(self(), test)

      Code.eval_string("""
        defmodule DeprecatedHandler do
          use Commanded.Event.Handler,
            application: Commanded.MockedApp,
            name: __MODULE__

          @impl Commanded.Event.Handler
          def init() do
            process_name = :"#{test}"
            Process.send(process_name, {:init, self()}, [])
          end
        end
      """)

      [handler: start_supervised!(DeprecatedHandler)]
    end

    test "should be called and a deprecation warning raised after handler subscribbed", %{
      handler: handler
    } do
      warning =
        capture_log([level: :warning], fn ->
          # When the handler subscribes to the eventstore
          send_subscribed(handler)

          # Then we expect init/0 to have been called for us
          assert_receive {:init, ^handler}
        end)

      # And we expect a deprecation warning to have been logged
      assert warning =~ "DeprecatedHandler.init/0 is deprecated, use after_start/1 instead"
    end
  end

  describe "event handler `after_start/1` callback" do
    defmodule AfterStartHandler do
      use Commanded.Event.Handler,
        application: Commanded.MockedApp,
        name: __MODULE__

      def after_start(state) do
        test_pid = Map.fetch!(state, :test)
        ref = Map.get_lazy(state, :ref, &make_ref/0)
        reply = Map.get(state, :reply, :ok)

        Process.send(test_pid, {ref, :after_start, reply}, [])
        reply
      end
    end

    test "should be called after handler subscribed" do
      ref = make_ref()
      state = %{test: self(), ref: ref}
      handler = start_supervised!({AfterStartHandler, state: state})

      refute_receive {^ref, :after_start, :ok}

      send_subscribed(handler)

      assert_receive {^ref, :after_start, :ok}
    end
  end

  defp send_subscribed(handler) do
    send(handler, {:subscribed, handler})
  end
end
