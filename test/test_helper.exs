ExUnit.start()

Mix.Task.run("event_store.create", ~w(--quiet))

case Application.get_env(:eventstore, :registry, :local) do
  :distributed -> EventStore.Cluster.spawn()
  _ -> :ok
end
