defmodule Commanded.StorageCase do
  use ExUnit.CaseTemplate
  use Commanded.EventStore

  require Logger

  setup do
    Application.stop(:commanded)
    Application.ensure_all_started(:commanded)
    :ok
  end
end
