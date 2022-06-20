defmodule Commanded.Subscriptions do
  @moduledoc false

  use GenServer

  alias Commanded.EventStore.RecordedEvent
  alias Commanded.PubSub
  alias Commanded.Subscriptions

  @ack_topic "ack_event"

  defstruct [
    :application,
    :streams_table,
    :started_at,
    subscribers: []
  ]

  def start_link(opts) do
    {start_opts, subscriptions_opts} =
      Keyword.split(opts, [:debug, :name, :timeout, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, subscriptions_opts, start_opts)
  end

  defdelegate register(application, name, module, pid \\ self(), consistency),
    to: Subscriptions.Registry

  defdelegate all(application), to: Subscriptions.Registry

  @doc """
  Acknowledge receipt and successful processing of the given event by the named
  handler.
  """
  def ack_event(application, name, consistency, event)

  def ack_event(_application, _name, :eventual, _event), do: :ok

  def ack_event(application, name, :strong, %RecordedEvent{} = event) do
    %RecordedEvent{stream_id: stream_id, stream_version: stream_version} = event

    PubSub.broadcast(application, @ack_topic, {:ack_event, name, stream_id, stream_version})
  end

  @doc false
  def reset(application) do
    name = name(application)

    GenServer.call(name, :reset)
  end

  @doc """
  Have all the registered handlers processed the given event?
  """
  def handled?(application, stream_uuid, stream_version, opts \\ []) do
    name = name(application)

    GenServer.call(name, {:handled?, stream_uuid, stream_version, opts})
  end

  @doc """
  Wait until all strongly consistent event store subscriptions have received
  and successfully handled the given event, by stream identity and version.

  Options:

    - `:consistency` - override the default consistency (`:strong`), by
      providing an explicit list of handler modules, or their configured names,
      to wait for.
    - `:exclude` - a PID, or list of PIDs, to exclude from waiting.

  Returns `:ok` on success, or `{:error, :timeout}` on failure due to timeout.
  """
  def wait_for(
        application,
        stream_uuid,
        stream_version,
        opts \\ [],
        timeout \\ default_consistency_timeout()
      ) do
    name = name(application)

    :ok = GenServer.call(name, {:subscribe, stream_uuid, stream_version, opts, self()})

    receive do
      {:ok, ^stream_uuid, ^stream_version} -> :ok
    after
      timeout ->
        :ok = GenServer.call(name, {:unsubscribe, self()})
        {:error, :timeout}
    end
  end

  def init(opts) do
    application = Keyword.fetch!(opts, :application)

    :ok = PubSub.subscribe(application, @ack_topic)

    schedule_purge_streams()

    {:ok, initial_state(application)}
  end

  def handle_call(:reset, _from, %Subscriptions{} = state) do
    %Subscriptions{application: application, streams_table: streams_table} = state

    :ets.delete(streams_table)

    {:reply, :ok, initial_state(application)}
  end

  def handle_call({:handled?, stream_uuid, stream_version, opts}, _from, %Subscriptions{} = state) do
    {consistency, exclude} = parse_opts(opts)

    reply = handled_by_all?(stream_uuid, stream_version, consistency, exclude, state)

    {:reply, reply, state}
  end

  def handle_call(
        {:subscribe, stream_uuid, stream_version, opts, pid},
        _from,
        %Subscriptions{} = state
      ) do
    {consistency, exclude} = parse_opts(opts)

    %Subscriptions{subscribers: subscribers} = state

    state =
      case handled_by_all?(stream_uuid, stream_version, consistency, exclude, state) do
        true ->
          # immediately notify subscriber since all handlers have already
          # processed the requested event
          notify_subscriber(pid, stream_uuid, stream_version)

          state

        false ->
          # subscribe process to be notified when the requested event has been
          # processed by all handlers
          Process.monitor(pid)

          subscription = {pid, stream_uuid, stream_version, consistency, exclude}

          %Subscriptions{state | subscribers: [subscription | subscribers]}
      end

    {:reply, :ok, state}
  end

  def handle_call({:unsubscribe, pid}, _from, %Subscriptions{} = state) do
    %Subscriptions{subscribers: subscribers} = state

    state = %Subscriptions{state | subscribers: remove_by_pid(subscribers, pid)}

    {:reply, :ok, state}
  end

  def handle_info({:ack_event, name, stream_uuid, stream_version}, %Subscriptions{} = state) do
    %Subscriptions{streams_table: streams_table, started_at: started_at} = state

    # track insert time as seconds since the subscriptions process was started
    # to support expiry of stale acks
    inserted_at_epoch = monotonic_time() - started_at

    :ets.insert(streams_table, {{name, stream_uuid}, stream_version, inserted_at_epoch})

    state = %Subscriptions{state | subscribers: notify_subscribers(stream_uuid, state)}

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

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %Subscriptions{} = state) do
    %Subscriptions{subscribers: subscribers} = state

    state = %Subscriptions{state | subscribers: remove_by_pid(subscribers, pid)}

    {:noreply, state}
  end

  defp initial_state(application) do
    %Subscriptions{
      application: application,
      streams_table: :ets.new(:streams, [:set, :private]),
      started_at: monotonic_time()
    }
  end

  # Have all subscriptions handled the event for the given stream and version
  defp handled_by_all?(
         stream_uuid,
         stream_version,
         consistency,
         exclude,
         %Subscriptions{} = state
       ) do
    %Subscriptions{application: application} = state

    Subscriptions.Registry.all(application)
    |> Enum.reject(fn {_name, _module, pid} -> MapSet.member?(exclude, pid) end)
    |> Enum.filter(fn {name, module, _pid} ->
      # Optionally filter subscriptions to those provided by the `consistency` option
      case consistency do
        :strong ->
          true

        consistency when is_list(consistency) ->
          Enum.member?(consistency, module) or Enum.member?(consistency, name)
      end
    end)
    |> Enum.all?(fn {name, _module, _pid} ->
      handled_by?(name, stream_uuid, stream_version, state)
    end)
  end

  # Has the named subscription handled the event for the given stream and version
  defp handled_by?(name, stream_uuid, stream_version, %Subscriptions{} = state) do
    %Subscriptions{streams_table: streams_table} = state

    case :ets.lookup(streams_table, {name, stream_uuid}) do
      [{{^name, ^stream_uuid}, last_seen, _inserted_at}] when last_seen >= stream_version -> true
      _ -> false
    end
  end

  defp remove_by_pid(subscribers, pid) do
    Enum.reduce(subscribers, subscribers, fn
      {^pid, _, _, _, _} = subscriber, subscribers -> subscribers -- [subscriber]
      _subscriber, subscribers -> subscribers
    end)
  end

  # Notify any subscribers waiting on a given stream if it is at the expected version
  defp notify_subscribers(stream_uuid, %Subscriptions{} = state) do
    %Subscriptions{subscribers: subscribers} = state

    Enum.reduce(subscribers, subscribers, fn
      {pid, ^stream_uuid, expected_stream_version, consistency, exclude} = subscriber,
      subscribers ->
        case handled_by_all?(stream_uuid, expected_stream_version, consistency, exclude, state) do
          true ->
            notify_subscriber(pid, stream_uuid, expected_stream_version)

            # Remove subscriber
            subscribers -- [subscriber]

          false ->
            subscribers
        end

      _subscriber, subscribers ->
        subscribers
    end)
  end

  defp notify_subscriber(pid, stream_uuid, stream_version) do
    send(pid, {:ok, stream_uuid, stream_version})
  end

  # Send an info message to the process to purge expired stream ack's
  defp schedule_purge_streams(ttl \\ default_ttl()) do
    Process.send_after(self(), {:purge_expired_streams, ttl}, ttl)
  end

  # Delete subscription ack's that are older than the configured ttl
  defp purge_expired_streams(ttl, %Subscriptions{} = state) do
    %Subscriptions{streams_table: streams_table, started_at: started_at} = state

    stale_epoch = monotonic_time() - started_at - ttl / 1_000

    streams_table
    |> :ets.select([{{:"$1", :"$2", :"$3"}, [{:"=<", :"$3", stale_epoch}], [:"$1"]}])
    |> Enum.each(&:ets.delete(streams_table, &1))
  end

  defp parse_opts(opts) do
    consistency = opts |> Keyword.get(:consistency, :strong) |> parse_consistency()
    exclude = opts |> Keyword.get(:exclude, []) |> parse_exclude()

    {consistency, exclude}
  end

  defp parse_consistency(consistency) when consistency in [:eventual, :strong], do: consistency

  defp parse_consistency(consistency) when is_list(consistency) do
    Enum.map(consistency, fn
      name when is_binary(name) -> name
      module when is_atom(module) -> module
      invalid -> raise ArgumentError, message: "invalid consistency: " <> inspect(invalid)
    end)
  end

  defp parse_consistency(invalid) do
    raise ArgumentError, message: "invalid consistency: " <> inspect(invalid)
  end

  defp parse_exclude(exclude), do: exclude |> List.wrap() |> MapSet.new()

  defp monotonic_time, do: System.monotonic_time(:second)

  defp name(application), do: Module.concat([application, __MODULE__])

  @default_ttl :timer.hours(1)
  @default_consistency_timeout :timer.seconds(5)

  # Time to live (ttl) period for ack'd events before they can be safely purged (in milliseconds).
  defp default_ttl do
    Application.get_env(:commanded, :subscriptions_ttl, @default_ttl)
  end

  defp default_consistency_timeout do
    Application.get_env(:commanded, :dispatch_consistency_timeout, @default_consistency_timeout)
  end
end
