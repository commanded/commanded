defmodule Commanded.Event.Registry do
  use GenServer
  require Logger

  alias Commanded.Event.Registry

  defstruct handlers: %{}

  def start_link do
    GenServer.start_link(__MODULE__, %Registry{}, name: __MODULE__)
  end

  @spec register(atom, Commanded.Event.Handler) :: :ok
  def register(command, handler) do
    GenServer.call(__MODULE__, {:register, command, handler})
  end

  @doc """
  Get all registered handlers for the given event
  """
  @spec handlers(map) :: [Commanded.Event.Handler]
  def handlers(event) when is_map(event) do
    GenServer.call(__MODULE__, {:handler, event.__struct__})
  end

  @doc """
  Get all registered handlers for the given event
  """
  @spec handlers(atom) :: [Commanded.Event.Handler]
  def handlers(event) when is_atom(event) do
    GenServer.call(__MODULE__, {:handlers, event})
  end

  def init(%Registry{} = state) do
    {:ok, state}
  end

  def handle_call({:register, event, handler}, _from, %Registry{handlers: handlers} = state) do
    state = case Map.get(handlers, event) do
      nil -> %Registry{state | handlers: Map.put(handlers, event, [handler])}
      event_handlers -> %Registry{state | handlers: Map.put(handlers, event, [handler | event_handlers])}
    end

    {:reply, :ok, state}
  end

  def handle_call({:handlers, event}, _from, %Registry{handlers: handlers} = state) do
    reply = case Map.get(handlers, event) do
      nil -> Logger.info("no handlers registered for event `#{inspect event}`")
        {:ok, []}
      handler -> {:ok, handler}
    end

    {:reply, reply, state}
  end
end
