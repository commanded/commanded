defmodule Commanded.Application.ConfigTest do
  use ExUnit.Case

  alias Commanded.Application.Config
  alias Commanded.ExampleApplication

  describe "a Commanded application" do
    setup do
      start_supervised!(ExampleApplication)

      :ok
    end

    test "should get application event store config" do
      assert {Commanded.EventStore.Adapters.InMemory,
              %{name: Commanded.ExampleApplication.EventStore}} ==
               Config.get(ExampleApplication, :event_store)
    end

    test "should get application pubsub config" do
      assert {Commanded.PubSub.LocalPubSub,
              %{
                pubsub_name: Commanded.ExampleApplication.LocalPubSub,
                tracker_name: Commanded.ExampleApplication.LocalPubSub.Tracker
              }} == Config.get(ExampleApplication, :pubsub)
    end

    test "should get application registry config" do
      assert {Commanded.Registration.LocalRegistry,
              %{registry_name: Commanded.ExampleApplication.LocalRegistry}} ==
               Config.get(ExampleApplication, :registry)
    end
  end
end
