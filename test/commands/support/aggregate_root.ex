defmodule Commanded.Commands.AggregateRoot do
  @moduledoc false
  alias Commanded.Commands.AggregateRoot

  defmodule Command, do: defstruct [uuid: nil]

  defstruct [uuid: nil]

  def execute(%AggregateRoot{}, %Command{}), do: []
end
