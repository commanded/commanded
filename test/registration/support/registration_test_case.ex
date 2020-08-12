defmodule Commanded.RegistrationTestCase do
  import Commanded.SharedTestCase

  define_tests do
    alias Commanded.Registration.{RegisteredServer, RegisteredSupervisor}

    setup do
      supervisor = start_supervised!(RegisteredSupervisor)

      [supervisor: supervisor]
    end

    describe "`start_child/3`" do
      test "should return child process PID on success", %{
        registry: registry,
        registry_meta: registry_meta
      } do
        assert {:ok, pid} = RegisteredSupervisor.start_child(registry, registry_meta, "child")
        assert is_pid(pid)
      end

      test "should return existing child process when already started", %{
        registry: registry,
        registry_meta: registry_meta
      } do
        assert {:ok, pid} = RegisteredSupervisor.start_child(registry, registry_meta, "child")
        assert {:ok, ^pid} = RegisteredSupervisor.start_child(registry, registry_meta, "child")
      end
    end

    describe "`start_link/3`" do
      test "should return process PID on success", %{
        registry: registry,
        registry_meta: registry_meta
      } do
        assert {:ok, pid} = start_link(registry, registry_meta, "registered")
        assert is_pid(pid)
      end

      test "should return existing process when already started", %{
        registry: registry,
        registry_meta: registry_meta
      } do
        assert {:ok, pid} = start_link(registry, registry_meta, "registered")
        assert {:ok, ^pid} = start_link(registry, registry_meta, "registered")
      end
    end

    describe "`whereis_name/1`" do
      test "should return `:undefined` when not registered", %{
        registry: registry,
        registry_meta: registry_meta
      } do
        assert registry.whereis_name(registry_meta, "notregistered") == :undefined
      end

      test "should return `PID` when child registered", %{
        registry: registry,
        registry_meta: registry_meta
      } do
        assert {:ok, pid} = RegisteredSupervisor.start_child(registry, registry_meta, "child")
        assert registry.whereis_name(registry_meta, "child") == pid
      end

      test "should return `PID` when process registered", %{
        registry: registry,
        registry_meta: registry_meta
      } do
        assert {:ok, pid} = start_link(registry, registry_meta, "registered")
        assert registry.whereis_name(registry_meta, "registered") == pid
      end
    end

    describe "`supervisor_child_spec/2`" do
      test "should return a valid child_spec", %{registry: registry, registry_meta: registry_meta} do
        assert registry.supervisor_child_spec(registry_meta, RegisteredSupervisor, "child") ==
                 %{
                   id: Commanded.Registration.RegisteredSupervisor,
                   start: {Commanded.Registration.RegisteredSupervisor, :start_link, ["child"]},
                   type: :supervisor
                 }
      end
    end

    defp start_link(registry, registry_meta, name) do
      registry.start_link(registry_meta, name, RegisteredServer, [], [])
    end
  end
end
