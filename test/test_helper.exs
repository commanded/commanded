ExUnit.start()

Mix.Task.run("event_store.create", ~w(--quiet))

Code.require_file("event_factory.ex", "test")
