defmodule Commanded.StorageCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  require Logger

  setup do
    Application.stop(:commanded)

    reset_storage()

    Application.ensure_all_started(:commanded)
    :ok
  end

  defp reset_storage do
    case Application.get_env(:commanded, :reset_storage) do
      nil -> :ok
      reset -> reset.()
    end
  end
end
