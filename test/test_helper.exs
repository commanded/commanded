ExUnit.start

Mix.Task.run("event_store.create", ~w(--quiet))

Code.require_file("event_factory.ex", "test")
Code.require_file("json_serializer.ex", "test")
Code.require_file("process_helper.ex", "test")
Code.require_file("storage_case.ex", "test")
Code.require_file("subscriber.ex", "test")
