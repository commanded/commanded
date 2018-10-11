defmodule Commanded.StorageCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  require Logger

  setup do
    on_exit(fn ->
      :ok = Application.stop(:commanded)

      {:ok, _apps} = Application.ensure_all_started(:commanded)
    end)
  end
end
