defmodule Commanded.Aggregates.SupervisorTest do
  use Commanded.StorageCase

  alias Commanded.ExampleDomain.BankAccount

  describe "open aggregate" do
    test "should ensure a string identity" do
      aggregate_uuid = "string"

      assert {:ok, ^aggregate_uuid} =
               Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, aggregate_uuid)
    end

    test "should not allow an integer, float, or atom as aggregate identity" do
      Enum.each([1, 1.2, :atom, ["foo"]], fn aggregate_uuid ->
        assert {:error, {:unsupported_aggregate_identity_type, ^aggregate_uuid}} =
                 Commanded.Aggregates.Supervisor.open_aggregate(BankAccount, aggregate_uuid)
      end)
    end
  end
end
