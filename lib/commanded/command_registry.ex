defmodule Commanded.CommandRegistry do
  use GenServer
  require Logger

  alias Commanded.CommandRegistry

  defstruct handlers: %{}

  def start_link do
    GenServer.start_link(__MODULE__, %CommandRegistry{}, name: __MODULE__)
  end

  @spec register(atom, Commanded.CommandHandler) :: :ok
  def register(command, handler) do
    GenServer.call(__MODULE__, {:register, command, handler})
  end

  @spec handler(atom) :: Commanded.CommandHandler
  def handler(command) do
    GenServer.call(__MODULE__, {:handler, command})
  end

  def init(%CommandRegistry{} = state) do
    {:ok, state}
  end

  def handle_call({:register, command, handler}, _from, %CommandRegistry{handlers: handlers} = state) do
    # prevent duplicate handlers for a command
    case Map.has_key?(handlers, command) do
      true -> {:reply, {:error, :already_registered}, state}
      false -> {:reply, :ok, %CommandRegistry{state | handlers: Map.put(handlers, command, handler)}}
    end
  end

  def handle_call({:handler, command}, _from, %CommandRegistry{handlers: handlers} = state) do
    reply = {:ok, Map.get(handlers, command)}
    {:reply, reply, state}
  end
end
