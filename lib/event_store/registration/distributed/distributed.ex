defmodule EventStore.Registration.Distributed do
  @moduledoc """
  Process registration and distribution throughout a cluster of nodes using [Swarm](https://github.com/bitwalker/swarm)
  """

  @behaviour EventStore.Registration

  def child_spec(_), do: []

  @spec register_name(name :: term, module :: atom, function :: atom, args :: [term]) :: {:ok, pid} | {:error, term}
  @impl EventStore.Registration
  def register_name(name, module, fun, args) do
    Swarm.register_name(name, module, fun, args)
  end

  @doc """
  Get the pid of a registered name.
  """
  @spec whereis_name(name :: term) :: pid | :undefined
  @impl EventStore.Registration
  def whereis_name(name) do
    Swarm.whereis_name(name)
  end

  defmacro __using__(_opts) do
    quote location: :keep do
      def via_tuple(name), do: {:via, :swarm, name}
    end
  end
end
