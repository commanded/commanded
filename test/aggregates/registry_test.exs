defmodule SupervisorTest do
  use Commanded.StorageCase

  test "should let use integer, atom or string as aggregate_uuid" do
    Enum.each([1, :atom, "string"], fn aggregate_uuid ->
      {:ok, _aggregate} = Commanded.Aggregates.Supervisor.open_aggregate(Commanded.ExampleDomain.BankAccount, aggregate_uuid)
    end)
  end
end
