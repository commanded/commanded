defmodule Commanded.ApplicationTest do
  use ExUnit.Case

  alias Commanded.Application
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
      assert Application.event_store_adapter(ExampleApplication) ==
               {Commanded.EventStore.Adapters.InMemory,
                %{name: Commanded.ExampleApplication.EventStore}}
    end

    test "should expose a pubsub adapter" do
      assert Application.pubsub_adapter(ExampleApplication) ==
               {Commanded.PubSub.LocalPubSub,
                %{
                  pubsub_name: Commanded.ExampleApplication.LocalPubSub,
                  tracker_name: Commanded.ExampleApplication.LocalPubSub.Tracker
                }}
    end

    test "should expose a registry adapter" do
      assert Application.registry_adapter(ExampleApplication) ==
               {Commanded.Registration.LocalRegistry,
                %{registry_name: Commanded.ExampleApplication.LocalRegistry}}
    end
  end
end
