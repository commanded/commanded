defmodule Commanded.Registration.Adapter do
  @moduledoc """
  Defines a behaviour for a process registry to be used by Commanded.

  By default, Commanded will use a local process registry, defined in
  `Commanded.Registration.LocalRegistry`, that uses Elixir's `Registry` module
  for local process registration. This limits Commanded to only run on a single
  node. However the `Commanded.Registration` behaviour can be implemented by a
  library to provide distributed process registration to support running on a
  cluster of nodes.
  """

  @type adapter_meta :: map()
  @type application :: Commanded.Application.t()
  @type config :: Keyword.t()
  @type start_child_arg :: {module(), Keyword.t()} | module()

  @doc """
  Return an optional supervisor spec for the registry
  """
  @callback child_spec(application, config) ::
              {:ok, [:supervisor.child_spec() | {module, term} | module], adapter_meta}

  @doc """
  Use to start a supervisor.
  """
  @callback supervisor_child_spec(adapter_meta, module :: atom, arg :: any()) ::
              :supervisor.child_spec()

  @doc """
  Starts a uniquely named child process of a supervisor using the given module
  and args.

  Registers the pid with the given name.
  """
  @callback start_child(
              adapter_meta,
              name :: term(),
              supervisor :: module(),
              child_spec :: start_child_arg
            ) ::
              {:ok, pid} | {:error, term}

  @doc """
  Starts a uniquely named `GenServer` process for the given module and args.

  Registers the pid with the given name.
  """
  @callback start_link(
              adapter_meta,
              name :: term(),
              module :: module(),
              args :: any(),
              start_options :: GenServer.options()
            ) :: {:ok, pid} | {:error, term}

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @callback whereis_name(adapter_meta, name :: term()) :: pid() | :undefined

  @doc """
  Return a `:via` tuple to route a message to a process by its registered name
  """
  @callback via_tuple(adapter_meta, name :: term()) :: {:via, module(), name :: term()}
end
