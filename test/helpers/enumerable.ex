defmodule Commanded.Enumerable do
  def pluck(enumerable, field) do
    Enum.map(enumerable, &Map.get(&1, field))
  end
end
