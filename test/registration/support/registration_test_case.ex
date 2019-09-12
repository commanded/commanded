defmodule Commanded.RegistrationTestCase do
  import Commanded.SharedTestCase

  define_tests do
    alias Commanded.DefaultApp
    alias Commanded.Registration
    alias Commanded.Registration.{RegisteredServer, RegisteredSupervisor}

    setup do
      start_supervised!(DefaultApp)

      {:ok, supervisor} = RegisteredSupervisor.start_link()

      [supervisor: supervisor]
    end

    describe "`start_child/3`" do
      test "should return child process PID on success" do
        assert {:ok, _pid} = RegisteredSupervisor.start_child(DefaultApp, "child")
      end

      test "should return existing child process when already started" do
        assert {:ok, pid} = RegisteredSupervisor.start_child(DefaultApp, "child")
        assert {:ok, ^pid} = RegisteredSupervisor.start_child(DefaultApp, "child")
      end
    end

    describe "`start_link/3`" do
      test "should return process PID on success" do
        assert {:ok, pid} = start_link("registered")
        assert is_pid(pid)
      end

      test "should return existing process when already started" do
        assert {:ok, pid} = start_link("registered")
        assert {:ok, ^pid} = start_link("registered")
      end
    end

    describe "`whereis_name/1`" do
      test "should return `:undefined` when not registered" do
        assert Registration.whereis_name(DefaultApp, "notregistered") == :undefined
      end

      test "should return `PID` when child registered" do
        assert {:ok, pid} = RegisteredSupervisor.start_child(DefaultApp, "child")
        assert Registration.whereis_name(DefaultApp, "child") == pid
      end

      test "should return `PID` when process registered" do
        assert {:ok, pid} = start_link("registered")
        assert Registration.whereis_name(DefaultApp, "registered") == pid
      end
    end

    describe "`supervisor_child_spec/2`" do
      test "should return a valid child_spec" do
        assert Registration.supervisor_child_spec(DefaultApp, RegisteredSupervisor, "child") ==
                 %{
                   id: Commanded.Registration.RegisteredSupervisor,
                   start: {Commanded.Registration.RegisteredSupervisor, :start_link, ["child"]},
                   type: :supervisor
                 }
      end
    end

    defp start_link(name) do
      Registration.start_link(DefaultApp, name, RegisteredServer, [])
    end
  end
end
