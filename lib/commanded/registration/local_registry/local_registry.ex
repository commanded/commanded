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
  Starts a `GenServer` process, and registers the pid with the given name.
  """
  @spec start_link(name :: term(), gen_server :: module(), args :: [any()]) :: {:ok, pid()} | {:error, reason :: term()}
  @impl Commanded.Registration
  def start_link(name, gen_server, args) do
    case whereis_name(name) do
      :undefined ->
        via_name = {:via, Registry, {Commanded.Registration.LocalRegistry, name}}

        case apply(GenServer, :start_link, [gen_server, args, [name: via_name]]) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _reason} = reply -> reply
        end

      pid ->
        {:ok, pid}
    end
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
