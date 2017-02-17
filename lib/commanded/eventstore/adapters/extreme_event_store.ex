if Code.ensure_loaded?(Extreme) do 
defmodule Commanded.EventStore.Adapters.ExtremeEventStore do

  @behaviour Commanded.EventStore

  require Logger

  use GenServer
  use Commanded.EventStore.Serializer

  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}
  alias Commanded.EventStore.Adapters.ExtremeSubscription
  alias Extreme.Messages, as: ExMsg

  @server Commanded.ExtremeEventStore
  @stream_prefix Commanded.Config.get(:commanded, :extreme, :streams_prefix)

  def start_link() do
    state = %{subscriptions: %{}}

    GenServer.start_link(__MODULE__, state, [name: __MODULE__])
  end

  @spec ack_event(pid, RecordedEvent.t) :: any
  def ack_event(subscription, %RecordedEvent{} = last_seen_event) do
    send(subscription, {:ack, last_seen_event.stream_version})
  end

  @spec append_to_stream(String.t, non_neg_integer, list(EventData.t)) :: {:ok, stream_version :: integer} | {:error, reason :: term}
  def append_to_stream(stream_uuid, expected_version, events) do
    stream = stream_name(stream_uuid)

    Logger.debug(fn -> "append to stream: #{stream} | #{inspect events}" end)

    add_to_stream(stream, expected_version, events)
  end

  @spec read_stream_forward(String.t, non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  def read_stream_forward(stream_uuid, start_version \\ 0, count \\ 1_000) do
    stream = stream_name(stream_uuid)
    start_version = normalize_start_version(start_version)

    read_forward(stream, start_version, count)
  end

  @spec stream_forward(String.t, non_neg_integer, non_neg_integer) :: Enumerable.t | {:error, reason :: term}
  def stream_forward(stream_uuid, start_version \\ 0, read_batch_size \\ 1_000) do
    stream = stream_name(stream_uuid)
    start_version = normalize_start_version(start_version)

    Stream.resource(
      fn -> {start_version, false} end,
      fn({next_version, halt?} = acc) ->
	case halt? do
	  true -> {:halt, acc}
	  false ->
	    case execute_read(stream, next_version, read_batch_size, :forward) do
	      {:ok, events, end_of_stream?} ->
		acc = {next_version + length(events), end_of_stream?}
		{events, acc}
	      {:error, :stream_not_found}=err -> {[err], {next_version, true}}
	    end
	end
      end,
      fn(_) -> :ok end
    )
  end

  @spec read_all_streams_forward(non_neg_integer, non_neg_integer) :: {:ok, list(RecordedEvent.t)} | {:error, reason :: term}
  def read_all_streams_forward(start_version \\ 0, count \\ 1_000) do
    stream = "$ce-#{@stream_prefix}"

    read_forward(stream, start_version, count)
  end

  @spec record_snapshot(SnapshotData.t) :: :ok | {:error, reason :: term}
  def record_snapshot(snapshot = %SnapshotData{}) do
    event_data = to_event_data(snapshot)
    stream = snapshot_stream(snapshot.source_uuid)
    
    Logger.debug(fn -> "record snapshot to stream: #{stream}" end)

    case add_to_stream(stream, :any_version, [event_data]) do
      {:ok, _} -> :ok
      err -> err
    end
  end
  
  @spec read_snapshot(String.t) :: {:ok, SnapshotData.t} | {:error, :snapshot_not_found}
  def read_snapshot(source_uuid) do
    stream = snapshot_stream(source_uuid)

    Logger.debug(fn -> "read snapshot from stream: #{stream}" end)

    case read_backward(stream, -1, 1) do
      {:ok, [recorded_event]} -> 
	{:ok, to_snapshot_data(recorded_event)}
      {:error, :stream_not_found} -> 
	{:error, :snapshot_not_found}
      err ->
	Logger.error(fn -> "error reading snapshot: #{inspect err}" end)
	err
    end
  end

  @spec subscribe_to_all_streams(String.t, pid, Commanded.EventStore.start_from) :: {:ok, subscription :: any}
    | {:error, :subscription_already_exists}
    | {:error, reason :: term}
  def subscribe_to_all_streams(subscription_name, subscriber, start_from \\ :origin, opts \\ []) do
    GenServer.call(__MODULE__, {:subscribe_all, subscription_name, subscriber, start_from, opts})
  end

  @spec unsubscribe_from_all_streams(String.t) :: :ok
  def unsubscribe_from_all_streams(subscription_name) do
    GenServer.call(__MODULE__, {:unsubscribe_all, subscription_name})
  end

  @spec delete_snapshot(String.t) :: :ok | {:error, reason :: term}
  def delete_snapshot(source_uuid) do
    stream = snapshot_stream(source_uuid)

    case Extreme.execute @server, delete_stream_msg(stream, false) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  def delete_stream(source_uuid) do
    stream = stream_name(source_uuid)

    case Extreme.execute @server, delete_stream_msg(stream, false) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  def handle_call({:unsubscribe_all, subscription_name}, _from, state) do
    {subscription_pid, subscriptions} = Map.pop(state.subscriptions, subscription_name)

    Process.exit(subscription_pid, :kill)

    {:reply, :ok, %{state | subscriptions: subscriptions}}
  end

  def handle_call({:subscribe_all, subscription_name, subscriber, start_from, opts}, _from, state) do
    case subscriber == Map.get(state.subscriptions, subscription_name) do
      true ->
	{:reply, {:error, :subscription_already_exists}, state}

      false ->
	stream = "$ce-#{@stream_prefix}"
	{:ok, pid} = ExtremeSubscription.start(stream, subscription_name, subscriber, start_from, opts)
	state = %{ state | subscriptions: Map.put(state.subscriptions, subscription_name, pid)}

	{:reply, ExtremeSubscription.result(pid), state}

    end
  end


  defp snapshot_stream(source_uuid), do: "#{@stream_prefix}snapshot-#{source_uuid}"

  defp stream_name(stream), do: "#{@stream_prefix}-#{stream}"

  defp normalize_start_version(start_version) do
    if (start_version > 0), do: start_version - 1, else: start_version
  end

  defp to_snapshot_data(event = %RecordedEvent{}) do
    data = event.data.source_type
    |> String.to_existing_atom
    |> struct(with_atom_keys(event.data.data))
    |> Commanded.Serialization.JsonDecoder.decode

    %SnapshotData{event.data |
      data: data,
      created_at: event.created_at
    }
  end

  defp with_atom_keys(map) do
    Enum.reduce(Map.keys(map), %{}, fn(key, m) ->
      Map.put(m, String.to_existing_atom(key), Map.get(map, key))
    end)
  end

  defp to_event_data(snapshot = %SnapshotData{}) do
    %EventData {
      correlation_id: nil,
      event_type: @serializer.to_event_name(SnapshotData),
      data: to_raw_event_data(snapshot),
      metadata: nil
    }
  end

  defp add_to_stream(stream, expected_version, events) do
    case Extreme.execute(@server, write_events(stream, expected_version, events)) do
      {:ok, response} ->
	{:ok, response.last_event_number + 1}
      {:error, :WrongExpectedVersion, detail} ->
	Logger.info(fn -> "Extreme eventstore wrong expected version '#{expected_version}': #{inspect detail}" end)
	{:error, :wrong_expected_version}
      err -> err
    end
  end

  defp delete_stream_msg(stream, hard_delete) do
    ExMsg.DeleteStream.new(
      event_stream_id: stream,
      expected_version: -2,
      require_master: false,
      hard_delete: hard_delete
    )
  end

  defp read_forward(stream, start_version, count) do
    execute_read!(stream, start_version, count, :forward)
  end

  defp read_backward(stream, start_version, count) do
    execute_read!(stream, start_version, count, :backward)
  end

  defp execute_read!(stream, start_version, count, direction) do
    case execute_read(stream, start_version, count, direction) do
      {:ok, events, _} -> {:ok, events}
      err -> err
    end
  end
  
  defp execute_read(stream, start_version, count, direction, read_events \\ []) do
    case Extreme.execute(@server, read_events(stream, start_version, count, direction)) do
      {:ok, %ExMsg.ReadStreamEventsCompleted{is_end_of_stream: end_of_stream?, events: events}=result} ->
	read_events = read_events ++ events

	if end_of_stream? || length(read_events) == count do
	  {:ok, Enum.map(read_events, &to_recorded_event/1), end_of_stream?}
	else
          # can occur with soft deleted streams
	  start_version =
	    case direction do
	      :forward -> result.next_event_number
	      :backward -> result.last_event_number
	    end
	  execute_read(stream, start_version, count, direction, read_events)
	end
      {:error, :NoStream, _} -> {:error, :stream_not_found}
      err -> err
    end
  end

  def to_recorded_event(ev = %Extreme.Messages.ResolvedIndexedEvent{}) do
    to_recorded_event(ev.event)
  end

  def to_recorded_event(ev = %Extreme.Messages.ResolvedEvent{}) do
    to_recorded_event(ev.event)
  end

  def to_recorded_event(ev = %Extreme.Messages.EventRecord{}) do
    event_id = UUID.binary_to_string!(ev.event_id)
    data = @serializer.deserialize(ev.data, [type: ev.event_type])
    {correlation_id, meta_data} =
      case ev.metadata do
	nil -> {nil, %{}}
	"" -> {nil, %{}}
	meta -> Map.pop(Poison.decode!(meta), "$correlationId")
      end
    
    %RecordedEvent{
      event_id: event_id,
      stream_id: to_stream_id(ev),
      stream_version: ev.event_number + 1,
      correlation_id: correlation_id,
      event_type: ev.event_type,
      data: data,
      metadata: meta_data,
      created_at: to_naive_date_time(ev.created_epoch)
    }
  end

  defp to_stream_id(ev = %Extreme.Messages.EventRecord{}) do
    prefix_len = 
      if Atom.to_string(SnapshotData) == ev.event_type do
	String.length("#{@stream_prefix}")
      else
	String.length("#{@stream_prefix}-")
      end

    String.slice(
      ev.event_stream_id,
      prefix_len,
      String.length(ev.event_stream_id)
    )
  end

  defp to_naive_date_time(millis_since_epoch) do
    secs_since_epoch = round(Float.floor(millis_since_epoch / 1000))
    millis = :erlang.rem(millis_since_epoch, 1000)
    epoch_secs = :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
    erl_date = :calendar.gregorian_seconds_to_datetime(epoch_secs + secs_since_epoch)
    
    NaiveDateTime.from_erl!(erl_date, {millis * 1000, 3})
  end

  defp read_events(stream, from_event_number, max_count, direction) do
    msg_type = if (:forward == direction), do: ExMsg.ReadStreamEvents, else: ExMsg.ReadStreamEventsBackward

    msg_type.new(
      event_stream_id: stream,
      from_event_number: from_event_number,
      max_count: max_count,
      resolve_link_tos: true,
      require_master: false
    )
  end

  defp to_raw_event_data(data) when is_map(data), do: @serializer.serialize(data)
  defp to_raw_event_data(data), do: data

  defp add_correlation_id(meta, cid)       when is_nil(meta) and is_binary(cid) do
    add_correlation_id(%{}, cid)
  end
  defp add_correlation_id(meta = %{}, cid) when is_binary(cid) do
    Map.put(meta, "$correlationId", cid)
  end
  defp add_correlation_id(meta, cid)       when is_nil(cid) do
    meta
  end
  defp add_correlation_id(meta, cid)       when is_binary(meta) do
    add_correlation_id(@serializer.deserialize(meta, []), cid)
  end
  defp add_correlation_id(meta, cid) do
    add_correlation_id(Map.from_struct(meta), cid)
  end

  defp write_events(stream_id, expected_version, events) do
    expected_version =
      case expected_version do
	:any_version -> -2
	_            -> expected_version - 1
      end

    proto_events = Enum.map(events, fn event ->
      meta_data = add_correlation_id(event.metadata, event.correlation_id)

      ExMsg.NewEvent.new(
        event_id: UUID.string_to_binary!(UUID.uuid4),
        event_type: event.event_type,
        data_content_type: 0,
        metadata_content_type: 0,
        data: to_raw_event_data(event.data),
        metadata: to_raw_event_data(meta_data)
      )
    end)

    ExMsg.WriteEvents.new(
      event_stream_id: stream_id, 
      expected_version: expected_version,
      events: proto_events,
      require_master: false
    )
  end

end
end
