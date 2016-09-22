defmodule RegistryTest do
  use ExUnit.Case

  alias Commanded.Aggregates.Registry

  setup do
    EventStore.Storage.reset!
    Commanded.Supervisor.start_link
    :ok
  end

  test "should let use integer, atom or string as aggregate_uuid" do
    Enum.each([1, :atom, "string"], fn aggregate_uuid ->
      {:ok, _aggregate} = Registry.open_aggregate(BankAccount, aggregate_uuid)
    end)
  end
end
