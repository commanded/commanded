defmodule Commanded.Registration.LocalRegistry do
  @moduledoc """
  Local process registration, restricted to a single node, using Elixir's
  [Registry](https://hexdocs.pm/elixir/Registry.html).
  """

  @behaviour Commanded.Registration

  @doc """
  Return an optional supervisor spec for the registry
  """
  @spec child_spec() :: [:supervisor.child_spec()]
  @impl Commanded.Registration
  def child_spec do
    [
      {Registry, keys: :unique, name: __MODULE__}
    ]
  end

  @doc """
  Starts a uniquely named child process of a supervisor using the given module
  and args.

  Registers the pid with the given name.
  """
  @spec start_child(name :: term(), supervisor :: module(), child_spec :: Commanded.Registration.start_child_arg) ::
          {:ok, pid} | {:error, term}
  @impl Commanded.Registration
  def start_child(name, supervisor, module) when is_atom(module) do
    via_name = {:via, Registry, {__MODULE__, name}}

    case DynamicSupervisor.start_child(supervisor, {module, [name: via_name]}) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      reply -> reply
    end
  end

  def start_child(name, supervisor, {module, args}) when is_list(args) do
    via_name = {:via, Registry, {__MODULE__, name}}
    updated_args = Keyword.put(args, :name, via_name)

    case DynamicSupervisor.start_child(supervisor, {module, updated_args}) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      reply -> reply
    end
  end

  @doc """
  Starts a uniquely named `GenServer` process for the given module and args.

  Registers the pid with the given name.
  """
  @spec start_link(name :: term(), module :: module(), args :: any()) ::
          {:ok, pid} | {:error, term}
  @impl Commanded.Registration
  def start_link(name, module, args) do
    via_name = {:via, Registry, {__MODULE__, name}}

    case GenServer.start_link(module, args, name: via_name) do
      {:error, {:already_started, pid}} -> {:ok, pid}
      reply -> reply
    end
  end

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @spec whereis_name(name :: term) :: pid | :undefined
  @impl Commanded.Registration
  def whereis_name(name), do: Registry.whereis_name({__MODULE__, name})

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @spec via_tuple(name :: term()) :: {:via, module(), name :: term()}
  @impl Commanded.Registration
  def via_tuple(name), do: {:via, Registry, {__MODULE__, name}}

  @doc false
  def handle_call(_request, _from, _state) do
    raise "attempted to call GenServer #{inspect(proc())} but no handle_call/3 clause was provided"
  end

  @doc false
  def handle_cast(_request, _state) do
    raise "attempted to cast GenServer #{inspect(proc())} but no handle_cast/2 clause was provided"
  end

  @doc false
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp proc do
    case Process.info(self(), :registered_name) do
      {_, []} -> self()
      {_, name} -> name
    end
  end
end
