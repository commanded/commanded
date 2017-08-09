defmodule EventStore.Registration do
  @moduledoc """
  Process registry specification
  """

  @doc """
  Starts a process using the given module/function/args parameters, and registers the pid with the given name.
  """
  @callback register_name(name :: term, module :: atom, function :: atom, args :: [term]) :: {:ok, pid} | {:error, term}

  @doc """
  Get the pid of a registered name.
  """
  @callback whereis_name(term) :: pid | :undefined
end
