defmodule Commanded.UUIDGenerator.AppUUIDGeneratorTest do
  use ExUnit.Case

  alias Commanded.UUIDGenerator.Stuff.Commands.MakeStuff
  alias Commanded.UUIDGenerator.IdApp
  alias Commanded.UUIDGenerator.IdDynamicApp
  alias Commanded.UUIDGenerator.IncorrectApp
  alias Commanded.UUIDGenerator.IdMiddleware
  alias Commanded.UUIDGenerator.IdGenerator

  describe "app uuid_generator option" do
    setup do
      start_supervised!(IdApp)
      start_supervised!(IdGenerator)
      start_supervised!(IdMiddleware)

      :ok
    end

    test "should trigger thrice for command_uuid, correlation_id and event_id" do
      command = %MakeStuff{stuff_id: 1, name: "Studio Ghibli"}

      assert :ok = IdApp.dispatch(command)
      assert %{command_uuid: 0, correlation_id: 1} = IdMiddleware.before_fields()
      assert IdMiddleware.before_fields() == IdMiddleware.after_fields()
      assert 3 == IdGenerator.current()
    end

    test "should trigger twice with correlation_id set" do
      command = %MakeStuff{stuff_id: 2, name: "My Neighbor Totoro"}

      assert :ok = IdApp.dispatch(command, correlation_id: "SET")
      assert %{command_uuid: 0, correlation_id: "SET"} = IdMiddleware.before_fields()
      assert 2 == IdGenerator.current()
    end

    test "should trigger twice with command_uuid set" do
      command = %MakeStuff{stuff_id: 3, name: "Satsuki"}

      assert :ok = IdApp.dispatch(command, command_uuid: "PUT")
      assert %{command_uuid: "PUT", correlation_id: 0} = IdMiddleware.before_fields()
      assert 2 == IdGenerator.current()
    end

    test "should trigger once with both command_uuid and correlation_id set" do
      command = %MakeStuff{stuff_id: 4, name: "Mae"}

      assert :ok = IdApp.dispatch(command, correlation_id: "TAKE", command_uuid: "REPLACE")
      assert %{command_uuid: "REPLACE", correlation_id: "TAKE"} = IdMiddleware.before_fields()
      assert 1 == IdGenerator.current()
    end

    test "should be empty/nil on before dispatch with dynamic apps" do
      start_supervised!({IdDynamicApp, name: IdDynamicApp.app_name(5)})

      command = %MakeStuff{stuff_id: 5, name: "Sampo"}

      assert :ok = IdDynamicApp.dispatch(command)
      assert %{command_uuid: nil, correlation_id: nil} = IdMiddleware.before_fields()
      assert %{command_uuid: 0, correlation_id: 1} = IdMiddleware.after_fields()
    end

    test "should fail with invalid app" do
      start_supervised!(IncorrectApp)

      command = %MakeStuff{stuff_id: 5, name: "Sampo"}

      assert_raise ArgumentError,
                   "invalid :uuid_generator config for application #{inspect(IncorrectApp)}",
                   fn -> IncorrectApp.dispatch(command) end

      refute IdMiddleware.before_fields()
      assert 0 == IdGenerator.current()
    end
  end
end
