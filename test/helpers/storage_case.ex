defmodule Commanded.StorageCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  require Logger

  alias Commanded.EventStore.Adapters.InMemory

  setup do
    on_exit(fn ->
      :ok = Application.stop(:commanded)

      InMemory.reset!()

      {:ok, _apps} = Application.ensure_all_started(:commanded)
    end)
  end
end
