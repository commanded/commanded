defmodule Commanded.ApplicationTest do
  use ExUnit.Case

  alias Commanded.EventStore.EventData
  alias Commanded.ExampleApplication

  describe "a Commanded application" do
    setup do
      start_supervised!(ExampleApplication)
      :ok
    end

    defmodule Event do
      @derive Jason.Encoder
      defstruct [:name]
    end

    test "should expose event store adapter" do
      assert ExampleApplication.__event_store_adapter__() == ExampleApplication.EventStore
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

    test "should expose pubsub adapter" do
      assert ExampleApplication.__pubsub_adapter__() == ExampleApplication.PubSub
    end

    test "should define a pubsub adapter" do
      assert_implements(ExampleApplication.PubSub, Commanded.PubSub.Adapter)
    end

    test "should expose registry adapter" do
      assert ExampleApplication.__registry_adapter__() == ExampleApplication.Registration
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
