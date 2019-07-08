defmodule Commanded.Registration.Adapter do
  @moduledoc false

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @adapter Keyword.fetch!(opts, :adapter)

      @behaviour Commanded.Registration.Adapter

      def child_spec, do: @adapter.child_spec(__MODULE__)

      def supervisor_child_spec(module, arg),
        do: @adapter.supervisor_child_spec(__MODULE__, module, arg)

      def start_child(name, supervisor, child_spec),
        do: @adapter.start_child(__MODULE__, name, supervisor, child_spec)

      def start_link(name, module, args), do: @adapter.start_link(__MODULE__, name, module, args)

      def whereis_name(name), do: @adapter.whereis_name(__MODULE__, name)

      def via_tuple(name), do: @adapter.via_tuple(__MODULE__, name)
    end
  end

  @doc """
  Return an optional supervisor spec for the registry.
  """
  @callback child_spec() :: [:supervisor.child_spec()]

  @doc """
  Use to start a supervisor.
  """
  @callback supervisor_child_spec(module :: atom, arg :: any()) :: :supervisor.child_spec()

  @doc """
  Starts a uniquely named child process of a supervisor using the given module
  and args.

  Registers the pid with the given name.
  """
  @callback start_child(
              name :: term(),
              supervisor :: module(),
              child_spec :: Commanded.Registration.start_child_arg()
            ) ::
              {:ok, pid} | {:error, term}

  @doc """
  Starts a uniquely named `GenServer` process for the given module and args.

  Registers the pid with the given name.
  """
  @callback start_link(name :: term(), module :: module(), args :: any()) ::
              {:ok, pid} | {:error, term}

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @callback whereis_name(name :: term()) :: pid() | :undefined

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name.
  """
  @callback via_tuple(name :: term()) :: {:via, module(), name :: term()}
end
