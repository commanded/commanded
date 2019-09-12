defmodule Commanded.ApplicationTest do
  use ExUnit.Case

  alias Commanded.Application
  alias Commanded.EventStore.EventData
  alias Commanded.ExampleApplication

  describe "a Commanded application" do
    setup do
      pid = start_supervised!(ExampleApplication)

      [pid: pid]
    end

    defmodule Event do
      @derive Jason.Encoder
      defstruct [:name]
    end

    test "should not allow an application to be started more than once", %{pid: pid} do
      assert {:error, {:already_started, ^pid}} = ExampleApplication.start_link()
    end

    test "should expose an event store adapter" do
      assert Application.event_store_adapter(ExampleApplication) == ExampleApplication.EventStore
    end

    test "should define an event store adapter" do
      assert_implements(ExampleApplication.EventStore, Commanded.EventStore.Adapter)

      events = [
        %EventData{
          correlation_id: UUID.uuid4(),
          causation_id: UUID.uuid4(),
          event_type: "#{__MODULE__}.Event",
          data: %Event{name: "1"},
          metadata: %{"metadata" => "value"}
        }
      ]

      assert :ok = ExampleApplication.EventStore.append_to_stream("1", 0, events)
    end

    test "should expose a pubsub adapter" do
      assert Application.pubsub_adapter(ExampleApplication) == ExampleApplication.PubSub
    end

    test "should define a pubsub adapter" do
      assert_implements(ExampleApplication.PubSub, Commanded.PubSub.Adapter)
    end

    test "should expose a registry adapter" do
      assert Application.registry_adapter(ExampleApplication) == ExampleApplication.Registration
    end

    test "should define a registration adapter" do
      assert_implements(ExampleApplication.Registration, Commanded.Registration.Adapter)
    end
  end

  # Returns `true` if module implements behaviour.
  defp assert_implements(module, behaviour) do
    all = Keyword.take(module.__info__(:attributes), [:behaviour])

    assert [behaviour] in Keyword.values(all)
  end
end
