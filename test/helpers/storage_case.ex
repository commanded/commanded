defmodule Commanded.StorageCase do
  use ExUnit.CaseTemplate
  use Commanded.EventStore

  require Logger
  
  setup do
    Application.stop(:commanded)

    reset_storage()

    Application.ensure_all_started(:commanded)
    :ok
  end

  defp reset_storage do
    case @event_store do
      Commanded.EventStore.Adapters.EventStoreEventStore -> 
	Application.ensure_all_started(:eventstore)
	reset_event_store_storage()
	Application.stop(:eventstore)
	Application.ensure_all_started(:eventstore)
      Commanded.EventStore.Adapters.ExtremeEventStore ->
	Application.ensure_all_started(:extreme)
	reset_extreme_storage()
	Application.stop(:extreme)
	Application.ensure_all_started(:extreme)
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

    wait_eventstore_ready()
  end

  defp wait_eventstore_ready do
    headers = ["Accept": "application/vnd.eventstore.atom+json"]
    options = [recv_timeout: 400]

    case HTTPoison.get "http://localhost:2113/streams/somestream", headers, options do
      {:ok, %HTTPoison.Response{status_code: 404}} ->
	:timer.sleep(400)
	:ok
      _ ->
	:timer.sleep(400)
	wait_eventstore_ready()
    end
  end
end
