defmodule Commanded.Commands.ExampleAggregate do
  alias Commanded.Commands.ExampleAggregate
  alias Commanded.Commands.ExampleCommand

  defstruct [:id]

  def execute(%ExampleAggregate{}, %ExampleCommand{}), do: []
end
