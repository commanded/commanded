defmodule Commanded.Subscriptions do
  @moduledoc false

  use GenServer

  alias Commanded.EventStore.RecordedEvent
  alias Commanded.{PubSub, Subscriptions}

  defstruct streams_table: nil,
            started_at: nil,
            subscribers: []

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @doc """
  Register an event store subscription with the given consistency guarantee.
  """
  def register(name, consistency)
  def register(_name, :eventual), do: :ok
  def register(name, :strong), do: PubSub.track(:subscriptions, name)

  @doc """
  Acknowledge receipt and sucessful processing of the given event by the named
  handler.
  """
  def ack_event(name, consistency, event)
  def ack_event(_name, :eventual, _event), do: :ok
  def ack_event(name, :strong, %RecordedEvent{stream_id: stream_id, stream_version: stream_version}) do
    PubSub.broadcast(__MODULE__, {:ack_event, name, stream_id, stream_version})
  end

  @doc false
  def all, do: subscriptions()

  @doc false
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @doc """
  Have all the registered handlers processed the given event?
  """
  def handled?(stream_uuid, stream_version, exclude \\ [])
  def handled?(stream_uuid, stream_version, exclude) do
    GenServer.call(__MODULE__, {:handled?, stream_uuid, stream_version, exclude})
  end

  @doc """
  Wait until all strongly consistent event store subscriptions have received
  and successfully handled the given event, by stream identity and version.

  Returns `:ok` on success, or `{:error, :timeout}` on failure due to timeout.
  """
  def wait_for(stream_uuid, stream_version, exclude \\ [], timeout \\ default_consistency_timeout())
  def wait_for(stream_uuid, stream_version, exclude, timeout) do
    :ok = GenServer.call(__MODULE__, {:subscribe, stream_uuid, stream_version, exclude, self()})

    receive do
      {:ok, ^stream_uuid, ^stream_version} -> :ok
    after
      timeout ->
        :ok = GenServer.call(__MODULE__, {:unsubscribe, self()})
        {:error, :timeout}
    end
  end

  def init(_arg) do
    :ok = PubSub.subscribe(__MODULE__)

    schedule_purge_streams()

    {:ok, initial_state()}
  end

  def handle_call(:reset, _from, %Subscriptions{streams_table: streams_table}) do
    :ets.delete(streams_table)

    {:reply, :ok, initial_state()}
  end

  def handle_call({:handled?, stream_uuid, stream_version, excluding}, _from, %Subscriptions{} = state) do
    reply = handled_by_all?(stream_uuid, stream_version, MapSet.new(excluding), state)

    {:reply, reply, state}
  end

  def handle_call({:subscribe, stream_uuid, stream_version, exclude, pid}, _from, %Subscriptions{subscribers: subscribers} = state) do
    exclusions = MapSet.new(exclude)
    state =
      case handled_by_all?(stream_uuid, stream_version, exclusions, state) do
        true ->
          # immediately notify subscriber since all handlers have already
          # processed the requested event
          notify_subscriber(pid, stream_uuid, stream_version)

          state

        false ->
          # subscribe process to be notified when the requested event has been
          # processed by all handlers
          Process.monitor(pid)

          %Subscriptions{state |
            subscribers: [{pid, stream_uuid, stream_version, exclusions} | subscribers]
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

  def handle_info({:ack_event, name, stream_uuid, stream_version}, %Subscriptions{} = state) do
    %Subscriptions{streams_table: streams_table, started_at: started_at} = state

    # track insert date as seconds since the subscriptions process was started
    # to support expiry of stale acks
    inserted_at_epoch = monotonic_time() - started_at

    :ets.insert(streams_table, {{name, stream_uuid}, stream_version, inserted_at_epoch})

    state = %Subscriptions{state |
      subscribers: notify_subscribers(stream_uuid, state),
    }

    {:noreply, state}
  end

  @doc """
  Purge stream acks that are older than the configured time-to-live (default is
  one hour).
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

  defp initial_state do
    %Subscriptions{
      streams_table: :ets.new(:streams, [:set, :private]),
      started_at: monotonic_time(),
    }
  end

  defp subscriptions, do: PubSub.list(:subscriptions)

  # Have all subscriptions handled the event for the given stream and version
  defp handled_by_all?(stream_uuid, stream_version, exclude, %Subscriptions{} = state) do
    subscriptions()
    |> Enum.reject(fn {_name, pid} -> MapSet.member?(exclude, pid) end)
    |> Enum.all?(fn {name, _pid} -> handled_by?(name, stream_uuid, stream_version, state) end)
  end

  # Has the named subscription handled the event for the given stream and version
  defp handled_by?(name, stream_uuid, stream_version, %Subscriptions{streams_table: streams_table}) do
    case :ets.lookup(streams_table, {name, stream_uuid}) do
      [{{^name, ^stream_uuid}, last_seen, _inserted_at}] when last_seen >= stream_version -> true
      _ -> false
    end
  end

  defp remove_by_pid(subscribers, pid) do
    Enum.reduce(subscribers, subscribers, fn
     ({^pid, _, _, _} = subscriber, subscribers) -> subscribers -- [subscriber]
     (_subscriber, subscribers) -> subscribers
    end)
  end

  # notify any subscribers waiting on a given stream if it is at the expected version
  defp notify_subscribers(stream_uuid, %Subscriptions{subscribers: subscribers} = state) do
    Enum.reduce(subscribers, subscribers, fn
      ({pid, ^stream_uuid, expected_stream_version, exclude} = subscriber, subscribers) ->
        case handled_by_all?(stream_uuid, expected_stream_version, exclude, state) do
          true ->
            notify_subscriber(pid, stream_uuid, expected_stream_version)

            # remove subscriber
            subscribers -- [subscriber]

          false ->
            subscribers
        end

      (_subscriber, subscribers) -> subscribers
    end)
  end

  defp notify_subscriber(pid, stream_uuid, stream_version) do
    send(pid, {:ok, stream_uuid, stream_version})
  end

  # send an info message to the process to purge expired stream ack's
  defp schedule_purge_streams(ttl \\ default_ttl()) do
    Process.send_after(self(), {:purge_expired_streams, ttl}, ttl)
  end

  # delete subscription ack's that are older than the configured ttl
  defp purge_expired_streams(ttl, %Subscriptions{streams_table: streams_table, started_at: started_at}) do
    stale_epoch = monotonic_time() - started_at - (ttl / 1_000)

    streams_table
    |> :ets.select([{{:"$1", :"$2", :"$3"}, [{:"=<", :"$3", stale_epoch}], [:"$1"]}])
    |> Enum.each(&:ets.delete(streams_table, &1))
  end

  defp monotonic_time, do: System.monotonic_time(:seconds)

  @default_ttl :timer.hours(1)
  @default_consistency_timeout :timer.seconds(5)

  # time to live period for ack'd events before they can be safely purged in milliseconds
  defp default_ttl,
    do: Application.get_env(:commanded, :subscriptions_ttl, @default_ttl)

  defp default_consistency_timeout,
    do: Application.get_env(:commanded, :dispatch_consistency_timeout, @default_consistency_timeout)
end
