defmodule Commanded.Aggregates.SupervisorTest do
  use Commanded.StorageCase

  defmodule CustomID do
    defstruct [:name, :scope]
  end

  defimpl String.Chars, for: CustomID do
    def to_string(%CustomID{name: name, scope: scope}), do: scope <> ":" <> name
  end

  describe "aggregate_uuid" do
    test "should allow an integer, atom or string" do
      Enum.each([1, :atom, "string"], fn aggregate_uuid ->
        {:ok, ^aggregate_uuid} = Commanded.Aggregates.Supervisor.open_aggregate(Commanded.ExampleDomain.BankAccount, aggregate_uuid)
      end)
    end

    test "should allow any object since it can be represented as a string" do
      custom_id = %CustomID{name: "bar", scope: "foo"}
      assert {:ok, "foo:bar"} == Commanded.Aggregates.Supervisor.open_aggregate(Commanded.ExampleDomain.BankAccount, custom_id)
    end
  end
end
