defmodule EventStore.StorageCase do
  use ExUnit.CaseTemplate

  setup do
    EventStore.StorageInitializer.reset_storage!()

    {:ok, conn} = EventStore.configuration() |> EventStore.Config.parse() |> Postgrex.start_link()
    
    {:ok, %{conn: conn}}
  end
end
