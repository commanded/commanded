defmodule Commanded do
  alias Commanded.Commands

  @doc """
  Dispatch the given command to the registered handler

  Returns `:ok` on success.
  """
  @spec dispatch(struct) :: :ok
  def dispatch(command) do
    Commands.Dispatcher.dispatch(command)
  end

  @doc """
  Register the given handler for the command

  Returns `:ok` on success, or `{:error, :already_registered}` if a handler has already been registered for the command.
  """
  @spec register(atom, Commanded.Commands.Handler) :: :ok | {:error, :already_registered}
  def register(command, handler) do
    Commands.Registry.register(command, handler)
  end
end
