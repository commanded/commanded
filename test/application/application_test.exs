defmodule Commanded.ApplicationTest do
  use ExUnit.Case

  alias Commanded.EventStore.Adapters.InMemory
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

    test "should return configured event store" do
      assert ExampleApplication.__event_store_adapter__() == InMemory
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

    test "should define a pubsub adapter" do
      assert_implements(ExampleApplication.PubSub, Commanded.PubSub.Adapter)
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
