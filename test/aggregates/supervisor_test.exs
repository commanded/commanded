defmodule Commanded.Aggregates.SupervisorTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.ExampleDomain.BankAccount

  describe "open aggregate" do
    setup do
      start_supervised!(DefaultApp)
      :ok
    end

    test "should ensure a string identity" do
      aggregate_uuid = "string"

      assert {:ok, ^aggregate_uuid} =
               Commanded.Aggregates.Supervisor.open_aggregate(
                 DefaultApp,
                 BankAccount,
                 aggregate_uuid
               )
    end

    test "should not allow an integer, float, or atom as aggregate identity" do
      Enum.each([1, 1.2, :atom, ["foo"]], fn aggregate_uuid ->
        assert {:error, {:unsupported_aggregate_identity_type, ^aggregate_uuid}} =
                 Commanded.Aggregates.Supervisor.open_aggregate(
                   DefaultApp,
                   BankAccount,
                   aggregate_uuid
                 )
      end)
    end
  end
end
