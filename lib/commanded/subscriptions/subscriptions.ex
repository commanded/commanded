defmodule Commanded.Subscriptions do
  @moduledoc false

  use GenServer

  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Subscriptions

  @subscriptions_table :subscriptions
  @streams_table :streams

  defstruct [
    subscribers: [],
  ]

  def start_link do
    GenServer.start_link(__MODULE__, %Subscriptions{}, name: __MODULE__)
  end

  @doc """
  Register an event store subscription with the given consistency guarantee
  """
  def register(name, consistency)
  def register(_name, :eventual), do: :ok
  def register(name, :strong) do
    GenServer.call(__MODULE__, {:register_subscription, name})
  end

  @doc """
  Acknowledge receipt and sucessful processing of the given event by the named handler
  """
  def ack_event(name, consistency, event)
  def ack_event(_name, :eventual, _event), do: :ok
  def ack_event(name, :strong, %RecordedEvent{stream_id: stream_id, stream_version: stream_version}) do
    GenServer.cast(__MODULE__, {:ack_event, name, stream_id, stream_version})
  end

  @doc false
  def all, do: subscriptions()

  @doc """
  Have all the registered handlers processed the given event?
  """
  def handled?(stream_uuid, stream_version) do
    GenServer.call(__MODULE__, {:handled?, stream_uuid, stream_version})
  end

  @doc """
  Wait until all strongly consistent event store subscriptions have received
  and successfully handled the given event, by stream identity and version.

  Returns `:ok` on success, or `{:error, :timeout}` on failure due to timeout.
  """
  def wait_for(stream_uuid, stream_version, timeout \\ default_consistency_timeout()) do
    :ok = GenServer.call(__MODULE__, {:subscribe, stream_uuid, stream_version, self()})

    receive do
      {:ok, ^stream_uuid, ^stream_version} -> :ok
    after
      timeout ->
        :ok = GenServer.call(__MODULE__, {:unsubscribe, self()})
        {:error, :timeout}
    end
  end

  def init(state) do
    _table = :ets.new(@subscriptions_table, [:set, :protected, :named_table])
    _table = :ets.new(@streams_table, [:set, :protected, :named_table])

    {:ok, state}
  end

  def handle_call({:handled?, stream_uuid, stream_version}, _from, %Subscriptions{} = state) do
    reply = handled_by_all?(stream_uuid, stream_version)

    {:reply, reply, state}
  end

  def handle_call({:subscribe, stream_uuid, stream_version, pid}, _from, %Subscriptions{subscribers: subscribers} = state) do
    state =
      case handled_by_all?(stream_uuid, stream_version) do
        true ->
          # immediately notify subscriber since all handlers have already processed the requested event
          notify_subscriber(pid, stream_uuid, stream_version)
          state

        false ->
          # subscribe process to be notified when the requested event has been processed by all handlers
          Process.monitor(pid)

          %Subscriptions{state |
            subscribers: [{pid, stream_uuid, stream_version} | subscribers]
          }
      end

    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, pid}, _from, %Subscriptions{subscribers: subscribers} = state) do
    state = %Subscriptions{state |
      subscribers: remove_by_pid(subscribers, pid),
    }

    {:reply, :ok, state}
  end

  def handle_call({:register_subscription, name}, _from, %Subscriptions{} = state) do
    :ets.insert(@subscriptions_table, {name})

    {:reply, :ok, state}
  end

  def handle_cast({:ack_event, name, stream_uuid, stream_version}, %Subscriptions{} = state) do
    :ets.insert(@streams_table, {{name, stream_uuid}, stream_version})

    state =
      case handled_by_all?(stream_uuid, stream_version) do
        true -> notify_subscribers(stream_uuid, stream_version, state)
        false -> state
      end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %Subscriptions{subscribers: subscribers} = state) do
    state = %Subscriptions{state |
      subscribers: remove_by_pid(subscribers, pid),
    }

    {:noreply, state}
  end

  # Have all subscriptions handled the event for the given stream and version
  defp handled_by_all?(stream_uuid, stream_version) do
    Enum.all?(subscriptions(), &handled_by?(&1, stream_uuid, stream_version))
  end

  # Has the named subscription handled the event for the given stream and version
  defp handled_by?(name, stream_uuid, stream_version) do
    case :ets.lookup(@streams_table, {name, stream_uuid}) do
      [{{^name, ^stream_uuid}, last_seen}] when last_seen >= stream_version -> true
      _ -> false
    end
  end

  defp subscriptions do
    @subscriptions_table
    |> :ets.tab2list()
    |> Enum.map(fn {name} -> name end)
  end

  defp remove_by_pid(subscribers, pid) do
    Enum.reduce(subscribers, subscribers, fn
     ({^pid, _, _} = subscriber, subscribers) -> subscribers -- [subscriber]
     (_subscriber, subscribers) -> subscribers
    end)
  end

  # Notify any subscribers who are waiting for handlers to have processed a given event
  defp notify_subscribers(_stream_uuid, _stream_version, %Subscriptions{subscribers: []} = state), do: state
  defp notify_subscribers(stream_uuid, stream_version, %Subscriptions{subscribers: subscribers} = state) do
    subscribers =
      Enum.reduce(subscribers, subscribers, fn
        ({pid, ^stream_uuid, expected_stream_uuid} = subscriber, subscribers) when expected_stream_uuid <= stream_version ->
          # notify subscriber and remove from subscribers list
          notify_subscriber(pid, stream_uuid, stream_version)
          subscribers -- [subscriber]

        (_subscriber, subscribers) -> subscribers
      end)

    %Subscriptions{state | subscribers: subscribers}
  end

  defp notify_subscriber(pid, stream_uuid, stream_version), do: send(pid, {:ok, stream_uuid, stream_version})

  defp default_consistency_timeout, do: Application.get_env(:commanded, :dispatch_consistency_timeout, 5_000)
end
