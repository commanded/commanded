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

  @doc """
  Publish events
  """
  @callback publish_events(stream_uuid :: term, events :: list(EventStore.RecordedEvent.t)) :: :ok

  # Get the configured registry provider, defaults to `:local` if not configured
  defp registry_provider do
    case Application.get_env(:eventstore, :registry, :local) do
      :local       -> EventStore.Registration.LocalRegistry
      :distributed -> EventStore.Registration.Distributed
      unknown      -> raise ArgumentError, message: "Unknown `:registry` setting in config: #{inspect unknown}"
    end
  end
end
