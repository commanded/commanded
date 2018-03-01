defmodule Commanded.StorageCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  require Logger

  setup do
    :ok = run_storage(:reset_storage)

    {:ok, _} = Application.ensure_all_started(:commanded)

    on_exit fn ->
      :ok = Application.stop(:commanded)
      :ok = run_storage(:stop_storage)
    end

    :ok
  end

  defp run_storage(name) do
    case Application.get_env(:commanded, name) do
      nil -> :ok
      fun when is_function(fun, 0) -> fun.()
    end
  end
end
