defmodule Commanded.Event.HandlerConfigTest do
  use ExUnit.Case

  alias Commanded.DefaultApp

  defmodule DefaultConfigHandler do
    use Commanded.Event.Handler,
      application: DefaultApp,
      name: __MODULE__
  end

  setup do
    start_supervised!(DefaultApp)
    :ok
  end

  test "should default to `:eventual` consistency and start from `:origin`" do
    {:ok, handler} = DefaultConfigHandler.start_link()

    assert_config(handler,
      application: Commanded.DefaultApp,
      name: "Commanded.Event.HandlerConfigTest.DefaultConfigHandler",
      concurrency: 1,
      consistency: :eventual,
      start_from: :origin,
      subscribe_to: :all
    )
  end

  describe "global config change to default consistency" do
    test "should use overridden default consistency" do
      Application.put_env(:commanded, :default_consistency, :strong)

      {:ok, handler} = DefaultConfigHandler.start_link()

      assert_config(handler,
        application: Commanded.DefaultApp,
        name: "Commanded.Event.HandlerConfigTest.DefaultConfigHandler",
        concurrency: 1,
        consistency: :strong,
        start_from: :origin,
        subscribe_to: :all
      )

      Application.put_env(:commanded, :default_consistency, :eventual)
    end
  end

  defmodule ExampleHandler do
    use Commanded.Event.Handler,
      application: Commanded.DefaultApp,
      name: __MODULE__,
      consistency: :strong,
      start_from: :current,
      subscribe_to: "stream1"
  end

  describe "config provided to `start_link/1`" do
    test "should use default config defined in handler when no opts passed to `start_link`" do
      {:ok, handler} = ExampleHandler.start_link()

      assert_config(handler,
        application: Commanded.DefaultApp,
        name: "Commanded.Event.HandlerConfigTest.ExampleHandler",
        concurrency: 1,
        consistency: :strong,
        start_from: :current,
        subscribe_to: "stream1"
      )
    end

    test "should use overridden config when provided" do
      {:ok, handler} =
        ExampleHandler.start_link(
          concurrency: 10,
          consistency: :eventual,
          index: 0,
          start_from: :origin,
          subscribe_to: "stream2"
        )

      assert_config(handler,
        application: Commanded.DefaultApp,
        name: "Commanded.Event.HandlerConfigTest.ExampleHandler",
        concurrency: 10,
        consistency: :eventual,
        start_from: :origin,
        subscribe_to: "stream2"
      )
    end

    test "should merge default config with provided opts" do
      {:ok, handler} = ExampleHandler.start_link(start_from: :origin)

      assert_config(handler,
        application: Commanded.DefaultApp,
        name: "Commanded.Event.HandlerConfigTest.ExampleHandler",
        concurrency: 1,
        consistency: :strong,
        start_from: :origin,
        subscribe_to: "stream1"
      )
    end

    test "allow name to be provided" do
      {:ok, handler} = ExampleHandler.start_link(name: "handler_name")

      assert_config(handler,
        application: Commanded.DefaultApp,
        name: "handler_name",
        concurrency: 1,
        consistency: :strong,
        start_from: :current,
        subscribe_to: "stream1"
      )
    end

    test "allow application to be provided" do
      start_supervised!({DefaultApp, name: :dynamic_app})

      {:ok, handler} = ExampleHandler.start_link(application: :dynamic_app)

      assert_config(handler,
        application: :dynamic_app,
        name: "Commanded.Event.HandlerConfigTest.ExampleHandler",
        concurrency: 1,
        consistency: :strong,
        start_from: :current,
        subscribe_to: "stream1"
      )
    end
  end

  describe "config provided to `child_spec`" do
    test "should use default config defined in handler when no overrides provided" do
      handler = start_supervised!(ExampleHandler)

      assert_config(handler,
        application: Commanded.DefaultApp,
        name: "Commanded.Event.HandlerConfigTest.ExampleHandler",
        concurrency: 1,
        consistency: :strong,
        start_from: :current,
        subscribe_to: "stream1"
      )
    end

    test "should use overridden config when provided" do
      start_supervised!({DefaultApp, name: :dynamic_app})

      handler =
        start_supervised!(
          {ExampleHandler,
           application: :dynamic_app,
           name: "handler_name",
           consistency: :eventual,
           start_from: :origin}
        )

      assert_config(handler,
        application: :dynamic_app,
        name: "handler_name",
        concurrency: 1,
        consistency: :eventual,
        start_from: :origin,
        subscribe_to: "stream1"
      )
    end
  end

  defmodule InvalidConfiguredHandler do
    use Commanded.Event.Handler,
      application: DefaultApp,
      name: __MODULE__,
      invalid_config_option: "invalid"
  end

  test "should validate provided config at runtime" do
    expected_error =
      "Commanded.Event.HandlerConfigTest.InvalidConfiguredHandler specifies invalid options: [:invalid_config_option]"

    assert_raise ArgumentError, expected_error, fn ->
      InvalidConfiguredHandler.start_link()
    end
  end

  defmodule RuntimeConfiguredHandler do
    use Commanded.Event.Handler
  end

  describe "runtime configured handler" do
    test "should require application" do
      expected_error =
        "Commanded.Event.HandlerConfigTest.RuntimeConfiguredHandler expects :application option"

      assert_raise ArgumentError, expected_error, fn ->
        RuntimeConfiguredHandler.start_link()
      end
    end

    test "should require name" do
      expected_error =
        "Commanded.Event.HandlerConfigTest.RuntimeConfiguredHandler expects :name option"

      assert_raise ArgumentError, expected_error, fn ->
        RuntimeConfiguredHandler.start_link(application: DefaultApp)
      end
    end

    test "started with runtime opts" do
      assert {:ok, _pid} =
               RuntimeConfiguredHandler.start_link(name: "handler1", application: DefaultApp)

      assert {:ok, _pid} =
               RuntimeConfiguredHandler.start_link(name: "handler2", application: DefaultApp)
    end

    test "start supervised with runtime opts" do
      start_supervised!({RuntimeConfiguredHandler, name: "handler1", application: DefaultApp})
      start_supervised!({RuntimeConfiguredHandler, name: "handler2", application: DefaultApp})
    end
  end

  defp assert_config(handler, expected_config) do
    alias Commanded.Event.Handler
    alias Commanded.EventStore.Subscription

    %Handler{
      application: application,
      handler_name: name,
      consistency: consistency,
      subscription: %Subscription{
        concurrency: concurrency,
        subscribe_from: subscribe_from,
        subscribe_to: subscribe_to
      }
    } = :sys.get_state(handler)

    actual_config = [
      application: application,
      name: name,
      concurrency: concurrency,
      consistency: consistency,
      start_from: subscribe_from,
      subscribe_to: subscribe_to
    ]

    assert actual_config == expected_config
  end
end
