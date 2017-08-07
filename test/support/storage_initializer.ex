defmodule EventStore.StorageInitializer do
  alias EventStore.Storage

  def reset_storage! do
    Application.stop(:eventstore)

    {:ok, conn} = EventStore.configuration() |> EventStore.Config.parse() |> Postgrex.start_link()

    Storage.Initializer.reset!(conn)

    {:ok, _} = Application.ensure_all_started(:eventstore)

    :ok
  end
end
