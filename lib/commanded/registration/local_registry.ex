defmodule Commanded.Registration.LocalRegistry do
  @moduledoc """
  Local process registration, restricted to a single node, using Elixir's [Registry](https://hexdocs.pm/elixir/Registry.html)
  """

  @behaviour Commanded.Registration

  @doc """
  Return an optional supervisor spec for the registry
  """
  @spec child_spec() :: [:supervisor.child_spec()]
  @impl Commanded.Registration
  def child_spec do
    [
      Supervisor.child_spec({Registry, [keys: :unique, name: Commanded.Registration.LocalRegistry]}, id: :commanded_local_registry),
    ]
  end

  @doc """
  Starts a uniquely named child process of a supervisor using the given module and args.

  Registers the pid with the given name.
  """
  @spec start_child(name :: term(), supervisor :: module(), args :: [any()]) :: {:ok, pid()} | {:error, reason :: term()}
  @impl Commanded.Registration
  def start_child(name, supervisor, args) do
    case whereis_name(name) do
      :undefined ->
        via_name = {:via, Registry, {Commanded.Registration.LocalRegistry, name}}

        Supervisor.start_child(supervisor, args ++ [[name: via_name]])

      pid ->
        {:ok, pid}
    end
  end

  @doc """
  Starts a uniquely named `GenServer` process for the given module and args.

  Registers the pid with the given name.
  """
  @spec start_link(name :: term(), module :: module(), args :: [any()]) :: {:ok, pid()} | {:error, reason :: term()}
  @impl Commanded.Registration
  def start_link(name, module, args) do
    case whereis_name(name) do
      :undefined ->
        via_name = {:via, Registry, {Commanded.Registration.LocalRegistry, name}}

        GenServer.start_link(module, args, [name: via_name])

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

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @spec via_tuple(name :: term()) :: {:via, module(), name :: term()}
  @impl Commanded.Registration
  def via_tuple(name), do: {:via, Registry, {Commanded.Registration.LocalRegistry, name}}
end
