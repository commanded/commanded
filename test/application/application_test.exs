defmodule Commanded.ApplicationTest do
  use ExUnit.Case

  alias Commanded.Application
  alias Commanded.ExampleApplication
  alias Commanded.RuntimeConfiguredApplication
  alias Commanded.UnconfiguredApplication

  describe "a Commanded application" do
    setup do
      pid = start_supervised!(ExampleApplication)

      [pid: pid]
    end

    test "should register process using application name", %{pid: pid} do
      assert Process.whereis(ExampleApplication) == pid
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

    test "should allow application config to be provided by `init/1` callback function" do
      start_supervised!(RuntimeConfiguredApplication)

      assert Application.event_store_adapter(RuntimeConfiguredApplication) ==
               {Commanded.EventStore.Adapters.InMemory,
                %{name: Commanded.RuntimeConfiguredApplication.EventStore}}

      assert Application.pubsub_adapter(RuntimeConfiguredApplication) ==
               {Commanded.PubSub.PhoenixPubSub,
                %{
                  pubsub_name: Commanded.RuntimeConfiguredApplication.PhoenixPubSub,
                  tracker_name: Commanded.RuntimeConfiguredApplication.PhoenixPubSub.Tracker
                }}

      assert Application.registry_adapter(RuntimeConfiguredApplication) ==
               {Commanded.Registration.LocalRegistry,
                %{registry_name: Commanded.RuntimeConfiguredApplication.LocalRegistry}}
    end

    test "should fail to start unconfigured application" do
      Process.flag(:trap_exit, true)

      UnconfiguredApplication.start_link()

      assert_receive {:EXIT, _pid,
                      {%ArgumentError{
                         message:
                           "missing :event_store config for application Commanded.UnconfiguredApplication"
                       }, _}}
    end
  end
end
