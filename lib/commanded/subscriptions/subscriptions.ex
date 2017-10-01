defmodule Commanded.Subscriptions do
  @moduledoc false

  use GenServer

  alias Commanded.EventStore.RecordedEvent
  alias Commanded.Subscriptions

  defstruct [
    subscriptions_table: nil,
    streams_table: nil,
    started_at: nil,
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
  def all do
    GenServer.call(__MODULE__, :all_subscriptions)
  end

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

  def init(%Subscriptions{} = state) do
    schedule_purge_streams()

    state = %Subscriptions{state |
      subscriptions_table: :ets.new(:subscriptions, [:set, :private]),
      streams_table: :ets.new(:streams, [:set, :private]),
      started_at: now(),
    }

    {:ok, state}
  end

  def handle_call(:all_subscriptions, _from, %Subscriptions{} = state) do
    reply = subscriptions(state)
    {:reply, reply, state}
  end

  def handle_call({:handled?, stream_uuid, stream_version}, _from, %Subscriptions{} = state) do
    reply = handled_by_all?(stream_uuid, stream_version, state)

    {:reply, reply, state}
  end

  def handle_call({:subscribe, stream_uuid, stream_version, pid}, _from, %Subscriptions{subscribers: subscribers} = state) do
    state =
      case handled_by_all?(stream_uuid, stream_version, state) do
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

  def handle_call({:register_subscription, name}, _from, %Subscriptions{subscriptions_table: subscriptions_table} = state) do
    :ets.insert(subscriptions_table, {name})

    {:reply, :ok, state}
  end

  def handle_cast({:ack_event, name, stream_uuid, stream_version}, %Subscriptions{streams_table: streams_table, subscriptions_table: subscriptions_table, started_at: started_at} = state) do
    # track insert date as ms since the subscripions process was started to support expiry of stale acks
    inserted_at_epoch = NaiveDateTime.diff(now(), started_at, :second)

    :ets.insert(subscriptions_table, {name})
    :ets.insert(streams_table, {{name, stream_uuid}, stream_version, inserted_at_epoch})

    state =
      case handled_by_all?(stream_uuid, stream_version, state) do
        true -> notify_subscribers(stream_uuid, stream_version, state)
        false -> state
      end

    {:noreply, state}
  end

  @doc """
  Purge stream acks that are older than the configured ttl (default is one hour).
  """
  def handle_info({:purge_expired_streams, ttl}, %Subscriptions{} = state) do
    purge_expired_streams(ttl, state)
    schedule_purge_streams(ttl)

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %Subscriptions{subscribers: subscribers} = state) do
    state = %Subscriptions{state |
      subscribers: remove_by_pid(subscribers, pid),
    }

    {:noreply, state}
  end

  # Have all subscriptions handled the event for the given stream and version
  defp handled_by_all?(stream_uuid, stream_version, %Subscriptions{} = state) do
    state
    |> subscriptions()
    |> Enum.all?(&handled_by?(&1, stream_uuid, stream_version, state))
  end

  # Has the named subscription handled the event for the given stream and version
  defp handled_by?(name, stream_uuid, stream_version, %Subscriptions{streams_table: streams_table}) do
    case :ets.lookup(streams_table, {name, stream_uuid}) do
      [{{^name, ^stream_uuid}, last_seen, _inserted_at}] when last_seen >= stream_version -> true
      _ -> false
    end
  end

  defp subscriptions(%Subscriptions{subscriptions_table: subscriptions_table}) do
    subscriptions_table
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

  # send an info message to the process to purge expired stream ack's
  defp schedule_purge_streams(ttl \\ default_ttl()) do
    Process.send_after(self(), {:purge_expired_streams, ttl}, ttl)
  end

  # delete subscription ack's that are older than the configured ttl
  defp purge_expired_streams(ttl, %Subscriptions{streams_table: streams_table, started_at: started_at}) do
    stale_epoch =
      now()
      |> NaiveDateTime.add(-ttl, :millisecond)
      |> NaiveDateTime.diff(started_at, :second)

    streams_table
    |> :ets.select([{{:"$1", :"$2", :"$3"}, [{:"=<", :"$3", stale_epoch}], [:"$1"]}])
    |> Enum.each(&:ets.delete(streams_table, &1))
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_naive()

  # time to live period for ack'd events before they can be safely purged in milliseconds
  @default_ttl :timer.hours(1)

  defp default_ttl, do: Application.get_env(:commanded, :subscriptions_ttl, @default_ttl)
  defp default_consistency_timeout, do: Application.get_env(:commanded, :dispatch_consistency_timeout, 5_000)
end
