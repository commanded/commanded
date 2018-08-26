alias Commanded.EventStore.Adapters.InMemory
alias Commanded.Serialization.JsonSerializer

{:ok, _pid} = InMemory.start_link(serializer: JsonSerializer)

ExUnit.start()
