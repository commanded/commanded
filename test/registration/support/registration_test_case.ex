defmodule Commanded.RegistrationTestCase do
  import Commanded.SharedTestCase

  define_tests do
    alias Commanded.Registration
    alias Commanded.Registration.{RegisteredServer, RegisteredSupervisor}

    setup %{application: application} do
      start_supervised!(application)
      supervisor = start_supervised!(RegisteredSupervisor)

      [supervisor: supervisor]
    end

    describe "`start_child/3`" do
      test "should return child process PID on success", %{application: application} do
        assert {:ok, _pid} = RegisteredSupervisor.start_child(application, "child")
      end

      test "should return existing child process when already started", %{
        application: application
      } do
        assert {:ok, pid} = RegisteredSupervisor.start_child(application, "child")
        assert {:ok, ^pid} = RegisteredSupervisor.start_child(application, "child")
      end
    end

    describe "`start_link/3`" do
      test "should return process PID on success", %{application: application} do
        assert {:ok, pid} = start_link(application, "registered")
        assert is_pid(pid)
      end

      test "should return existing process when already started", %{application: application} do
        assert {:ok, pid} = start_link(application, "registered")
        assert {:ok, ^pid} = start_link(application, "registered")
      end
    end

    describe "`whereis_name/1`" do
      test "should return `:undefined` when not registered", %{application: application} do
        assert Registration.whereis_name(application, "notregistered") == :undefined
      end

      test "should return `PID` when child registered", %{application: application} do
        assert {:ok, pid} = RegisteredSupervisor.start_child(application, "child")
        assert Registration.whereis_name(application, "child") == pid
      end

      test "should return `PID` when process registered", %{application: application} do
        assert {:ok, pid} = start_link(application, "registered")
        assert Registration.whereis_name(application, "registered") == pid
      end
    end

    describe "`supervisor_child_spec/2`" do
      test "should return a valid child_spec", %{application: application} do
        assert Registration.supervisor_child_spec(application, RegisteredSupervisor, "child") ==
                 %{
                   id: Commanded.Registration.RegisteredSupervisor,
                   start: {Commanded.Registration.RegisteredSupervisor, :start_link, ["child"]},
                   type: :supervisor
                 }
      end
    end

    defp start_link(application, name) do
      Registration.start_link(application, name, RegisteredServer, [])
    end
  end
end
