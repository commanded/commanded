defmodule RegistryTest do
  use Commanded.StorageCase

  alias Commanded.Aggregates.Registry

  test "should let use integer, atom or string as aggregate_uuid" do
    Enum.each([1, :atom, "string"], fn aggregate_uuid ->
      {:ok, _aggregate} = Registry.open_aggregate(BankAccount, aggregate_uuid)
    end)
  end
end
