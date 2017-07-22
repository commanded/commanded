ExUnit.start()

Mix.Task.run("event_store.create", ~w(--quiet))
