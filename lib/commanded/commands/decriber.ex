defmodule Commanded.Commands.Describer do
  @moduledoc false

  @fields_to_filter Application.get_env(:commanded, :filter_fields, [])

  def describe(data) do
    data = Enum.reduce(Map.from_struct(data), %{}, fn {key, val}, acc -> 
      if key in @fields_to_filter do
        Map.put(acc, key, "[FILTERED]")
      else
        Map.put(acc, key, val)
      end
    end)

    "#{inspect(data)}"
  end
end
