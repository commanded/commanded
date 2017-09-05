defmodule EventStore.Registration.LocalRegistry do
  @moduledoc """
  Local process registration, restricted to a single node, using Elixir's [Registry](https://hexdocs.pm/elixir/Registry.html)
  """

  @behaviour EventStore.Registration

  alias EventStore.Registration.LocalRegistry.Supervisor

  def child_spec do
    [
      Supervisor.child_spec([]),
    ]
  end

  @doc """
  Starts a process using the given module/function/args parameters, and registers the pid with the given name.
  """
  @spec register_name(name :: term, module :: atom, function :: atom, args :: [term]) :: {:ok, pid} | {:error, term}
  @impl EventStore.Registration
  def register_name(name, module, fun, [supervisor, args]) do
    name = {:via, Registry, {EventStore.Registration.LocalRegistry, name}}

    apply(module, fun, [supervisor, args ++ [[name: name]]])
  end

  @doc """
  Get the pid of a registered name.
  """
  @spec whereis_name(name :: term) :: pid | :undefined
  @impl EventStore.Registration
  def whereis_name(name)
  def whereis_name(name), do: Registry.whereis_name({EventStore.Registration.LocalRegistry, name})

  @doc """
  Publish events
  """
  @callback publish_events(stream_uuid :: term, events :: list(EventStore.RecordedEvent.t)) :: :ok
  @impl EventStore.Registration
  def publish_events(stream_uuid, events) do
    send(EventStore.Publisher, {:notify_events, stream_uuid, events})
  end

  defmacro __using__(_opts) do
    quote location: :keep do
      def via_tuple(name), do: {:via, Registry, {EventStore.Registration.LocalRegistry, name}}
    end
  end
end
