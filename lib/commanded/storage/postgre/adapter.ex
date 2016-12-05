defmodule Commanded.Storage.Postgre.Adapter do
  alias Commanded.Storage.Postgre.Mapper
  @behaviour Commanded.Storage.Adapter

  @type aggregate_uuid      :: String.t
  @type start_version       :: String.t
  @type batch_size          :: integer()
  @type batch               :: list()
  @type reason              :: atom()


  # @spec load_events(aggregate_uuid, start_version, batch_size)
  #       :: {:ok, batch} | {:error, reason}


    @doc "Save a list of events to the stream."
    def append_to_stream(stream_id, expected_version,  pending_events) do
      correlation_id = UUID.uuid4
      event_data = Mapper.map_to_event_data(pending_events, correlation_id)
      :ok = EventStore.append_to_stream(stream_id, expected_version, event_data)
    end

    # @doc "Load all events for that stream"
    # def load_all_events(stream) do
    # end
    #
    # @doc "Load events, but from a specific position"
    # def load_events(stream, position, batch_size \\ @read_event_batch_size) do
    #   EventStore.read_stream_forward(stream, position, batch_size)
    # end
    #
    # @doc "snapshot adding -snapshot to its stream name"
    # def append_snapshot(stream, state) do
    # end
    #
    # @doc "Load the last snapshot for that stream"
    # def load_snapshot(stream) do
    # end


end



  # PROCESS ROUTER SNIPETS

  # defp persist_state(%ProcessManagerInstance{process_manager_module: process_manager_module, process_state: process_state} = state, event_id) do
  #   :ok = EventStore.record_snapshot(%EventStore.Snapshots.SnapshotData{
  #     source_uuid: process_state_uuid(state),
  #     source_version: event_id,
  #     source_type: Atom.to_string(process_manager_module),
  #     data: process_state
  #   })
  # end
  #
  #
  #


  # def handle_cast({:fetch_state}, %ProcessManagerInstance{} = state) do
  #   state = case EventStore.read_snapshot(process_state_uuid(state)) do
  #     {:ok, snapshot} ->
  #       %ProcessManagerInstance{state |
  #         process_state: snapshot.data,
  #         last_seen_event_id: snapshot.source_version,
  #       }
  #
  #     {:error, :snapshot_not_found} ->
  #       state
  #   end
  #
  #   {:noreply, state}
  # end



  # def handle_cast({:process_event, %EventStore.RecordedEvent{event_id: event_id} = event, process_router}, %ProcessManagerInstance{command_dispatcher: command_dispatcher, process_manager_module: process_manager_module, process_state: process_state} = state) do
  #   case handle_event(process_manager_module, process_state, event) do
  #     {:error, reason} ->
  #       Logger.warn(fn -> "process manager instance failed to handle event id #{inspect event_id} due to: #{inspect reason}" end)
  #       {:noreply, state}
  #
  #     commands ->
  #       :ok = dispatch_commands(List.wrap(commands), command_dispatcher)
  #
  #       process_state = mutate_state(process_manager_module, process_state, event)
  #
  #       state = %ProcessManagerInstance{state |
  #         process_state: process_state,
  #         last_seen_event_id: event_id,
  #       }
  #
  #       persist_state(state, event_id)
  #       ack_event(event, process_router)
  #
  #       {:noreply, state}
  #   end
  # end
