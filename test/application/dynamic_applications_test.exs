defmodule Commanded.DynamicApplicationsTest do
  use ExUnit.Case

  alias Commanded.ExampleApplication

  describe "dynamic Commanded applications" do
    test "should allow name to be provided when starting an application" do
      assert {:ok, pid} = start_supervised({ExampleApplication, name: :example1})
      assert Process.whereis(:example1) == pid
    end

    test "should not allow an application to be started more than once with the same name" do
      assert {:ok, pid} = start_supervised({ExampleApplication, name: :example1})
      assert {:error, {:already_started, ^pid}} = ExampleApplication.start_link(name: :example1)
    end

    test "should allow the same application to be started multiple times with dynamic names" do
      assert {:ok, pid1} = start_supervised({ExampleApplication, name: :example1})
      assert {:ok, pid2} = start_supervised({ExampleApplication, name: :example2})
      assert {:ok, pid3} = start_supervised({ExampleApplication, name: :example3})

      assert length(Enum.uniq([pid1, pid2, pid3])) == 3
    end
  end
end
