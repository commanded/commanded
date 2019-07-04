defmodule Commanded.Aggregates.AggregateConcurrencyTest do
  use ExUnit.Case

  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.Serialization.JsonSerializer

  defmodule ExampleApplication do
    use Commanded.Application,
      otp_app: :commanded,
      event_store: [
        adapter: InMemory,
        serializer: JsonSerializer
      ]
  end

  describe "a Commanded application" do
    test "should return configured event store" do
      assert ExampleApplication.__event_store_adapter__() == InMemory
      assert ExampleApplication.__event_store_config__() == [serializer: JsonSerializer]
    end
  end
end
