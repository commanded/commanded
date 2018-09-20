defmodule Commanded.RegistrationTestCase do
  import Commanded.SharedTestCase

  define_tests do
    alias Commanded.Registration
    alias Commanded.Registration.{RegisteredServer, RegisteredSupervisor}

    setup %{registry: registry} do
      Application.put_env(:commanded, :registry, registry)

      {:ok, supervisor} = RegisteredSupervisor.start_link()

      on_exit(fn ->
        Application.delete_env(:commanded, :registry)
      end)

      [supervisor: supervisor]
    end

    describe "`start_child/3`" do
      test "should return child process PID on success" do
        assert {:ok, _pid} = RegisteredSupervisor.start_child("child")
      end

      test "should return existing child process when already started" do
        assert {:ok, pid} = RegisteredSupervisor.start_child("child")
        assert {:ok, ^pid} = RegisteredSupervisor.start_child("child")
      end
    end

    describe "`start_link/3`" do
      test "should return process PID on success" do
        assert {:ok, _pid} = start_link("registered")
      end

      test "should return existing process when already started" do
        assert {:ok, pid} = start_link("registered")
        assert {:ok, ^pid} = start_link("registered")
      end
    end

    describe "`whereis_name/1`" do
      test "should return `:undefined` when not registered" do
        assert Registration.whereis_name("notregistered") == :undefined
      end

      test "should return `PID` when child registered" do
        assert {:ok, pid} = RegisteredSupervisor.start_child("child")
        assert Registration.whereis_name("child") == pid
      end

      test "should return `PID` when process registered" do
        assert {:ok, pid} = start_link("registered")
        assert Registration.whereis_name("registered") == pid
      end
    end

    defp start_link(name) do
      Registration.start_link(name, RegisteredServer, [name])
    end
  end
end
