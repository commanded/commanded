ExUnit.start(exclude: [:distributed])

Mix.Task.run("event_store.create", ~w(--quiet))

case Application.get_env(:eventstore, :registry) do
  :distributed -> EventStore.Cluster.spawn()
  _ -> :ok
end
