defmodule EventStore.StorageInitializer do
  def reset_storage! do
    with {:ok, conn} <- EventStore.configuration() |> EventStore.Config.parse() |> Postgrex.start_link() do
      EventStore.Storage.Initializer.reset!(conn)
    end

    :ok
  end
end
