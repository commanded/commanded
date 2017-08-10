defmodule EventStore.Registration do
  @moduledoc """
  Process registry specification
  """

  defmacro __using__(_) do
    registry = registry_provider()

    quote do
      @registry unquote(registry)

      use unquote(registry)
    end
  end

  @doc """
  Starts a process using the given module/function/args parameters, and registers the pid with the given name.
  """
  @callback register_name(name :: term, module :: atom, function :: atom, args :: [term]) :: {:ok, pid} | {:error, term}

  @doc """
  Get the pid of a registered name.
  """
  @callback whereis_name(term) :: pid | :undefined

  defp registry_provider do
    Application.get_env(:eventstore, :registry, :local)
    |> case do
      :local       -> EventStore.Registration.LocalRegistry
      :distributed -> EventStore.Registration.Distributed
      unknown      -> raise ArgumentError, message: "Unknown :registry setting in config: #{inspect unknown}"
    end
  end
end
