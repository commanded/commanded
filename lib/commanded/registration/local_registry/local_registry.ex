defmodule Commanded.Registration.LocalRegistry do
  @moduledoc """
  Local process registration, restricted to a single node, using Elixir's [Registry](https://hexdocs.pm/elixir/Registry.html)
  """

  @behaviour Commanded.Registration

  def child_spec do
    [
      Supervisor.child_spec({Registry, [keys: :unique, name: Commanded.Registration.LocalRegistry]}, id: :commanded_local_registry),
    ]
  end

  @doc """
  Starts a process using the given module/function/args parameters, and registers the pid with the given name.
  """
  @spec register_name(name :: term, module :: atom, function :: atom, args :: [term]) :: {:ok, pid} | {:error, term}
  @impl Commanded.Registration
  def register_name(name, module, fun, [supervisor, args]) do
    name = {:via, Registry, {Commanded.Registration.LocalRegistry, name}}

    apply(module, fun, [supervisor, args ++ [[name: name]]])
  end

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @spec whereis_name(name :: term) :: pid | :undefined
  @impl Commanded.Registration
  def whereis_name(name), do: Registry.whereis_name({Commanded.Registration.LocalRegistry, name})

  defmacro __using__(_opts) do
    quote location: :keep do
      def via_tuple(name), do: {:via, Registry, {Commanded.Registration.LocalRegistry, name}}
    end
  end
end
