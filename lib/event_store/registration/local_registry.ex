defmodule EventStore.Registration.LocalRegistry do
  @moduledoc """
  Local process registration, restricted to a single node, using Elixir's [Registry](https://hexdocs.pm/elixir/Registry.html)
  """

  @behaviour EventStore.Registration

  alias EventStore.Publisher

  @doc """
  Return the local supervisor child spec
  """
  @spec child_spec() :: [:supervisor.child_spec()]
  @impl EventStore.Registration
  def child_spec do
    [
      Supervisor.child_spec({Registry, [keys: :unique, name: EventStore.Registration.LocalRegistry]}, id: :event_store_local_registry),
    ]
  end

  @doc """
  Starts a uniquely named child process of a supervisor using the given module and args.

  Registers the pid with the given name.
  """
  @spec start_child(name :: term(), supervisor :: module(), args :: [any()]) :: {:ok, pid()} | {:error, reason :: term()}
  @impl EventStore.Registration
  def start_child(name, supervisor, args) do
    case whereis_name(name) do
      :undefined ->
        via_name = {:via, Registry, {EventStore.Registration.LocalRegistry, name}}

        Supervisor.start_child(supervisor, args ++ [[name: via_name]])

      pid ->
        {:ok, pid}
    end
  end

  @doc """
  Get the pid of a registered name.
  """
  @spec whereis_name(name :: term) :: pid | :undefined
  @impl EventStore.Registration
  def whereis_name(name), do: Registry.whereis_name({EventStore.Registration.LocalRegistry, name})

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @spec via_tuple(name :: term()) :: {:via, module(), name :: term()}
  @impl EventStore.Registration
  def via_tuple(name), do: {:via, Registry, {EventStore.Registration.LocalRegistry, name}}

  @doc """
  Publish events to the `EventStore.Publisher` process
  """
  @callback publish_events(stream_uuid :: term, events :: list(EventStore.RecordedEvent.t)) :: :ok
  @impl EventStore.Registration
  def publish_events(stream_uuid, events) do
    Publisher.notify_events(Publisher, stream_uuid, events)
  end
end
