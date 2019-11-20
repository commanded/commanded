defmodule Commanded.Application.ConfigTest do
  use ExUnit.Case

  alias Commanded.Application.Config
  alias Commanded.ExampleApplication
  alias Commanded.Helpers.Wait

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

    test "should remove config when application stopped" do
      :ok = stop_supervised(ExampleApplication)

      Wait.until(fn ->
        assert_raise(
          RuntimeError,
          "could not lookup Commanded.ExampleApplication because it was not started or it does not exist",
          fn ->
            Config.get(ExampleApplication, :event_store)
          end
        )
      end)
    end
  end
end
