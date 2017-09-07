defmodule Commanded.Aggregates.SupervisorTest do
  use Commanded.StorageCase

  test "should allow an integer, atom, or string as an aggregate_uuid" do
    Enum.each([1, :atom, "string"], fn aggregate_uuid ->
      {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(Commanded.ExampleDomain.BankAccount, aggregate_uuid)
    end)
  end
end
