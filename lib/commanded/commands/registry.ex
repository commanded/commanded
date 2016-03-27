defmodule Commanded.Commands.Registry do
  use GenServer
  require Logger

  alias Commanded.Commands.Registry

  defstruct handlers: %{}

  def start_link do
    GenServer.start_link(__MODULE__, %Registry{}, name: __MODULE__)
  end

  @spec register(atom, Commanded.Commands.Handler) :: :ok
  def register(command, handler) do
    GenServer.call(__MODULE__, {:register, command, handler})
  end

  @spec handler(atom) :: Commanded.Commands.Handler
  def handler(command) do
    GenServer.call(__MODULE__, {:handler, command})
  end

  def init(%Registry{} = state) do
    {:ok, state}
  end

  def handle_call({:register, command, handler}, _from, %Registry{handlers: handlers} = state) do
    # prevent duplicate handlers for a command
    case Map.has_key?(handlers, command) do
      true -> {:reply, {:error, :already_registered}, state}
      false -> {:reply, :ok, %Registry{state | handlers: Map.put(handlers, command, handler)}}
    end
  end

  def handle_call({:handler, command}, _from, %Registry{handlers: handlers} = state) do
    reply = {:ok, Map.get(handlers, command)}
    {:reply, reply, state}
  end
end
