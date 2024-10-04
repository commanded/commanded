defmodule Commanded.Registration.HandleDelegationTest do
  use ExUnit.Case

  alias Commanded.Aggregates.Aggregate
  alias Commanded.Registration.HandleFunctionDelegationApp

  setup do
    start_supervised!(HandleFunctionDelegationApp)

    :ok
  end

  describe "delegate to clauses defined in registry" do
    test "handle_call/3" do
      assert :bar == Aggregate.handle_call(:foo, :whatever, state())
    end

    test "handle_cast/2" do
      assert :baz == Aggregate.handle_cast(:bar, state())
    end

    test "handle_info/2" do
      assert :yahoo == Aggregate.handle_info(:baz, state())
    end

    defp state do
      %{application: HandleFunctionDelegationApp}
    end
  end
end
