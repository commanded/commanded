defmodule EventStore.Registration.Distributed do
  @moduledoc """
  Process registration and distribution throughout a cluster of nodes using [Swarm](https://github.com/bitwalker/swarm)
  """

  @behaviour EventStore.Registration

  def child_spec(_config, serializer) do
    [
      publisher_spec(serializer),
    ]
  end

  @spec register_name(name :: term, module :: atom, function :: atom, args :: [term]) :: {:ok, pid} | {:error, term}
  @impl EventStore.Registration
  def register_name(name, module, fun, args) do
    case Swarm.register_name(name, module, fun, args) do
      {:error, {:already_registered, pid}} -> {:error, {:already_started, pid}}
      reply -> reply
    end
  end

  @doc """
  Get the pid of a registered name.
  """
  @spec whereis_name(name :: term) :: pid | :undefined
  @impl EventStore.Registration
  def whereis_name(name), do: Swarm.whereis_name(name)

  @doc """
  Joins the current process to a group
  """
  @spec join(group :: term) :: :ok
  @impl EventStore.Registration
  def join(group), do: Swarm.join(group, self())

  @doc """
  Publishes a message to a group.
  """
  @spec publish(group :: term, msg :: term) :: :ok
  @impl EventStore.Registration
  def publish(group, msg), do: Swarm.publish(group, msg)

  defmacro __using__(_opts) do
    quote location: :keep do
      def via_tuple(name), do: {:via, :swarm, name}
    end
  end

  def publisher_spec(serializer) do
    %{
      id: EventStore.Publisher,
      restart: :permanent,
      shutdown: 5000,
      start: {EventStore.Registration.Distributed, :register_name, [EventStore.Publisher, EventStore.Publisher, :start_link, [serializer]]},
      type: :worker,
    }
  end
end
