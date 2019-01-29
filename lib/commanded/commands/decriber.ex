defmodule Commanded.Commands.Describer do
  @moduledoc """
  Commands describer is used to describe a command, mostly for filtering sensitive data from being exposed in log outputs.

  ## Example
      config :commanded, :filter_fields, [:password, :secret_key]
  """

  @doc """
  Helper to transform a command to a safe exposable string by filtering configured keys.
  """
  def describe(data) do
    to_filter = Application.get_env(:commanded, :filter_fields, [])
    data = Enum.reduce(Map.from_struct(data), %{}, fn {key, val}, acc -> 
      if key in to_filter do
        Map.put(acc, key, "[FILTERED]")
      else
        Map.put(acc, key, val)
      end
    end)

    "#{inspect(data)}"
  end
end
