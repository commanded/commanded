defmodule EventStore.Registration.LocalRegistry do
  @moduledoc """
  Local process registration, restricted to a single node, using Elixir's [Registry](https://hexdocs.pm/elixir/Registry.html)
  """

  @behaviour EventStore.Registration

  alias EventStore.Registration.LocalRegistry.Supervisor

  def child_spec(config), do: Supervisor.child_spec(config)

  @spec register_name(name :: term, module :: atom, function :: atom, args :: [term]) :: {:ok, pid} | {:error, term}
  def register_name(name, module, fun, [supervisor, args]) do
    name = {:via, Registry, {EventStore.Registration.LocalRegistry, name}}

    apply(module, fun, [supervisor, args ++ [name]])
  end

  @doc """
  Get the pid of a registered name.
  """
  @spec whereis_name(name :: term) :: pid | :undefined
  def whereis_name(name) do
    Registry.whereis_name({EventStore.Registration.LocalRegistry, name})
  end

  defmacro __using__(_opts) do
    quote location: :keep do
      def via_tuple(name), do: {:via, Registry, {EventStore.Registration.LocalRegistry, name}}
    end
  end
end
