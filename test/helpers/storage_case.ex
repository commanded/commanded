defmodule Commanded.StorageCase do
  use ExUnit.CaseTemplate
  use Commanded.EventStore

  require Logger
  
  setup do
    Application.stop(:commanded)
    Application.stop(:eventstore)

    reset_storage

    Application.ensure_all_started(:commanded)
    :ok
  end

  defp reset_storage do
    case @event_store do
      Commanded.EventStore.Adapters.EventStoreEventStore -> 
	reset_event_store_storage
      Commanded.EventStore.Adapters.ExtremeEventStore ->
	reset_extreme_storage
    end
  end

  defp reset_event_store_storage do
    storage_config = Application.get_env(:eventstore, EventStore.Storage)

    {:ok, conn} = Postgrex.start_link(storage_config)

    EventStore.Storage.Initializer.reset!(conn)
  end

  defp reset_extreme_storage do
    server = %{
      baseUrl: "http://localhost:2375",
      ssl_options: [
	{:certfile, 'docker.crt'},
	{:keyfile, 'docker.key'},
      ]
    }
    container_name = "commanded-tests-eventstore"

    {:ok, conn} = Docker.start_link server

    Docker.Container.kill conn, container_name
    Docker.Container.delete conn, container_name
    Docker.Container.create conn, container_name, %{
      "Image": "eventstore/eventstore",
      "ExposedPorts": %{
	"2113/tcp" => %{},
	"1113/tcp" => %{}
      },
      "PortBindings": %{
	"1113/tcp": [%{ "HostPort" => "1113" }],
	"2113/tcp": [%{ "HostPort" => "2113" }]
      },
      "Env": [
	"EVENTSTORE_DB=/tmp/db",
	"EVENTSTORE_RUN_PROJECTIONS=All",
	"EVENTSTORE_START_STANDARD_PROJECTIONS=True"
      ]
    }
    Docker.Container.start conn, container_name

    :timer.sleep(2400)
  end
end
