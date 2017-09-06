defmodule Commanded.Registration do
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
  Starts a child of a supervisor, and registers the pid with the given name.
  """
  @callback start_child(name :: term(), supervisor :: module(), args :: [any()]) :: {:ok, pid()} | {:error, reason :: term()}

  @doc """
  Starts a `GenServer` process, and registers the pid with the given name.
  """
  @callback start_link(name :: term(), gen_server :: module(), args :: [any()]) :: {:ok, pid()} | {:error, reason :: term()}

  @doc """
  Get the pid of a registered name.

  Returns `:undefined` if the name is unregistered.
  """
  @callback whereis_name(term()) :: pid() | :undefined

  # get the configured registry provider
  defp registry_provider do
    case Application.get_env(:commanded, :registry) do
      nil -> raise ArgumentError, "Commanded expects `:registry` to be configured in environment"
      :local -> Commanded.Registration.LocalRegistry
      other -> other
    end
  end
end
