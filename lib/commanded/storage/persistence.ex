defmodule Commanded.Storage.Persistence do
  @moduledoc """
  The triangle: Aggregate Data Structure + Server's State (Container) + Side Effects
  This module encapsulates the Database side-efects over the aggregate's container. 
  The ideia is to have one point to reload the aggregate that lives inside the server's state,
  that I called here: container. So the logic needed to find it on snapshot and replay from the
  events that come afterwards are all encapsulated here. Theorically, it should be private functions
  inside the aggregate's server, but for easier testing, debuging, and maintaining, the rehydrate
  function will be the interface for this small sub-engine.
  Easier to test, debug and mantain :) . So we focus only on retrieving and persisting data here,
  creating new pids, and other decisions should be make by the server, repository and router.
  If you come from OO, imagine that this module is like: 
  https://en.wikipedia.org/wiki/Java_Persistence_Query_Language, but differently, we receive the 
  data-structure, process side-effects, and give back the updated data-structure

  Note that when we snapshot, we save the server state, that contains the aggregate data structure,
  and we need to replay the remaining events only from the data structure. 
  The flow should be this: Load a snapshot, if found, replay events from there, 
    Load snapshot -> found    -> replay from there -> not found, return the snapshot
                                                      found, replay
                    not found -> try replay from scratch -> not found -> return a new data strcuture
                                                        found     -> replay
  It's optimistic, and try to find a solution. It's specially useful for process managers, that want
  to make snapshot for each state change (i.e. zero snapshot period), and automatically return the last
  one, even trying to read the following events.
  TODO: add ckecksum sync, to guarantee the counter state is the same as returned by the stream
  TODO: refactor and organize specs, rename bang functions
  """


  defstruct uuid: nil,                  # uuid, obvious
            name: nil,                  # use it to concatenate to the UUID and give a meaningful name
            counter: 0,                 # event counter, we receive the event position from the db
            version: 0,
            pending_events: [],         # events pending to be applied [we reset it after applying
            snapshot_period: 40,
            module: nil,                # the module name of the aggregate pure functional data structure 
            #snapshot_period: nil,       # every number of event, we snapshot
            state: nil,                 # the data structure  process_manager | state
            dispatcher: nil,            # used specifically by the process manager
            last_seen_event_id: nil     # used specifically by the process manager


  require Logger
  #require Engine.Aggregate.Aggregate.State
  alias Engine.Container
  alias Engine.Storage.Storage

  @typedoc "positions -> [first, last]"
  @type state     :: struct()           # the aggregate or process manager data structure
  @type container :: struct()           # the server that holds the aggregate data structure
  @type positions :: list(integer)      # positions from first and last saved events, i.e. {:ok, [3,5]}
  @type events    :: [struct()]
  @type uuid      :: String.t


  #@spec rehydrate(module, uuid)            :: aggregate
  @spec rehydrate(module, uuid)            :: state
  @spec append_events(state)               :: state
  @spec append_snapshot(state)             :: state
  @spec persist(state)      :: state
  #@spec load_events(container)             :: {:error, any()} | {:ok, events}
  #@spec load_snapshot(container)          :: {:error, any()} | {:ok, container}


  @doc "Receive a module that implements apply function, and rebuild the state from events"
  def apply_events(module, state, events), do:
    Enum.reduce(events, state, &module.apply(&2, &1))


  #### API #########
  @doc """
  If we find a snapshot for this stream, we replay from that state position, 
  and if the snapshot is not find, we try to replay from scratch, and if not, 
  we give back the same empty container, once it's suposed to be a new one
  """
  # def rehydrate(%Container{module: module, uuid: uuid} = container) do
  #   new_state = rehydrate(module, uuid)
  #   %{container | state: new_state}
  # end

  @doc """
  Main function API for writing, with auto-snapshot, that means, you append the events, and it
  will check inside the container, the event position and the snapshot period, and if it matches,
  it will automaticall generate a snapshot for this container. We first must append events and clean
  the pending events before snapshoting, so we will have a clean snapshot state written on the disk.
  TODO: sanity check, sync counter with last
  """
  # def persist(%Container{state: state} = container) do
  #   new_state = persist(state)
  #   %{container | state: new_state}
  # end



  ##### INTERNAL #####
 
  @doc "Main facade functions for testing with aggregates and process managers data structures"
  def rehydrate(module, uuid) do
    load_snapshot(module, uuid)
      |> replay_events(module)
  end

  @doc "Main facade functions for testing with aggregates and process managers data structures"
  def persist(aggregate) do
      aggregate
        |> append_events                      # append events and also CLEAN the pending ones !
        |> append_snapshot                    # now we pipe to snapshot
  end



  @doc """
  Load the last snapshot for this container, and rebuild state based on module. If we can't load
  the snapshot for any reason, we return a new fresh datastructure, and in caller function, 
  events will be played from strach
  """
  def load_snapshot(module, uuid) do
    case Storage.load_snapshot(uuid) do
      {:ok, snapshot} ->
        agg = module.new(uuid)                           # struct State in runtime, but the module is a macro
        state = agg.state                                # so we create a new datastructre to "template" it out
        new_state = struct_from_map(snapshot.state, as: state)  # our map has keys as strings
        %{snapshot | state: new_state}                   # so we need a custom converter
      {:error, reason} ->
        Logger.debug "Snapshot unloaded for #{uuid} because #{reason}, so creating a fresh data structure"
        module.new(uuid)
    end
  end


  @doc "rebuild an aggregate from a given snapshot, and replay events if found afterwards"
  def replay_events(aggregate, module) do
    case Storage.load_events(aggregate.uuid, aggregate.counter) do
      {:ok, events}    -> module.load(aggregate, events) #aggregate |> module.load(events)
      {:error, reason} -> replay_from_events(module, aggregate.uuid)
    end
  end

  @doc "recostitute a containter from scratch"
  def replay_from_events(module, uuid, snapshot_period \\ 10) do
    aggregate = case Storage.load_all_events(uuid) do
      {:ok, events}    -> module.load(uuid, events)
      {:error, reason} -> module.new(uuid, snapshot_period)
    end
    %{aggregate | pending_events: []}                    # events list should only include uncommitted events
  end


  @doc "append events to the stream, reset pending events and update counter"
  def append_events(aggregate) do
    case Storage.append_events(aggregate.uuid, aggregate.pending_events) do
      {:ok, [first, last]} -> %{aggregate | pending_events: []}
      {:error, reason}     ->
        Logger.error "Appending events failed for #{aggregate} because #{reason}"
        aggregate
    end
  end

  @doc "automatically decide if it's the right time to snapshot based on the snapshot period"
  def append_snapshot(aggregate) do
    case mod(aggregate.counter, aggregate.snapshot_period) do
      true  -> case Storage.append_snapshot(aggregate.uuid, aggregate) do
                  {:ok, [first, last]} -> aggregate
                  {:error, reason}     ->
                    Logger.error "Snapshoting aggregate failed for #{aggregate} because #{reason}"
                    aggregate
               end
      false -> aggregate
    end
  end

  @doc "load events from a spcecific position [extracts position from the aggregate inside]"
  # def load_events(%Container{uuid: uuid, state: aggregate} = server), do:
  #   Storage.load_events(uuid, aggregate.counter)


  @doc "create structs from maps when KEYs are strings...., oi vei"
  defp struct_from_map(a_map, as: a_struct) do
    # Find the keys within the map
    keys = Map.keys(a_struct)
             |> Enum.filter(fn x -> x != :__struct__ end)
    # Process map, checking for both string / atom keys
    processed_map =
     for key <- keys, into: %{} do
         value = Map.get(a_map, key) || Map.get(a_map, to_string(key))
         {key, value}
       end
    a_struct = Map.merge(a_struct, processed_map)
    a_struct
  end

  @doc "C = counter, P = position, it returns true if the counter beats the position"
  defp mod(0,p),             do: true    # we snapshot the state from the first event
  defp mod(c,p) when c  < p, do: false
  defp mod(c,p) when c >= p  do
    case rem c,p do
      0 -> true
      _ -> false
    end
  end


end


  # defp populate_aggregate_state(%Aggregate{aggregate_module: aggregate_module} = state) do
  #   rebuild_from_events(%Aggregate{state |
  #     aggregate_version: 0,
  #     aggregate_state: struct(aggregate_module)
  #   })
  # end
  #
  # defp rebuild_from_events(%Aggregate{} = state), do: rebuild_from_events(state, 1)
  #
  # # load events from the event store, in batches of 100 events, to rebuild the aggregate state
  # defp rebuild_from_events(%Aggregate{aggregate_uuid: aggregate_uuid, aggregate_module: aggregate_module, aggregate_state: aggregate_state} = state, start_version) do
  #   case EventStore.read_stream_forward(aggregate_uuid, start_version, @read_event_batch_size) do
  #     {:ok, batch} ->
  #       batch_size = length(batch)
  #
  #       # rebuild the aggregate's state from the batch of events
  #       aggregate_state = apply_events(aggregate_module, aggregate_state, map_from_recorded_events(batch))
  #
  #       state = %Aggregate{state |
  #         aggregate_version: start_version - 1 + batch_size,
  #         aggregate_state: aggregate_state
  #       }
  #
  #       case batch_size < @read_event_batch_size do
  #         true ->
  #           # end of event stream for aggregate so return its state
  #           state
  #
  #         false ->
  #           # fetch next batch of events to apply to updated aggregate state
  #           rebuild_from_events(state, start_version + @read_event_batch_size)
  #       end
  #
  #     {:error, :stream_not_found} ->
  #       # aggregate does not exist so return empty state
  #       state
  #   end
  # end
  #
  # defp execute_command(command, handler, %Aggregate{aggregate_uuid: aggregate_uuid, aggregate_version: expected_version, aggregate_state: aggregate_state, aggregate_module: aggregate_module} = state) do
  #   case execute_command(handler, aggregate_state, command) do
  #     {:error, _reason} = reply -> {reply, state}
  #     nil -> {:ok, state}
  #     [] -> {:ok, state}
  #     events ->
  #       pending_events = List.wrap(events)
  #
  #       updated_state = apply_events(aggregate_module, aggregate_state, pending_events)
  #
  #       :ok = persist_events(pending_events, aggregate_uuid, expected_version)
  #
  #       state = %Aggregate{state |
  #         aggregate_state: updated_state,
  #         aggregate_version: expected_version + length(pending_events),
  #       }
  #
  #       {:ok, state}
  #   end
  # end
  #
  # defp execute_command(handler, aggregate_state, command) do
  #   handler.handle(aggregate_state, command)
  # end
  #
  # defp apply_events(aggregate_module, aggregate_state, events) do
  #   Enum.reduce(events, aggregate_state, &aggregate_module.apply(&2, &1))
  # end



  # @doc "if we succeed in appending events, we clean the data structure, if not, we send it back"
  # def append_events(%Container{uuid: uuid, aggregate: aggregate} = server) do
  #   case Storage.append_events(uuid, aggregate.pending_events) do
  #     {:ok, counter}   -> server = %{server | pending_events: []}
  #     {:error, reason} ->
  #       Logger.error "Error in appending data"
  #       aggregate
  #   end
  # end





  # defp load_events(%Aggregate{aggregate_module: aggregate_module, aggregate_uuid: aggregate_uuid} = state) do
  #   aggregate_state = case EventStore.read_stream_forward(aggregate_uuid) do
  #     {:ok, events} -> aggregate_module.load(aggregate_uuid, map_from_recorded_events(events))
  #     {:error, :stream_not_found} -> aggregate_module.new(aggregate_uuid)
  #   end
  #
  #   # events list should only include uncommitted events
  #   aggregate_state = %{aggregate_state | pending_events: []}
  #
  #   %Aggregate{state | aggregate_state: aggregate_state}
  # end
  #
  # def handle_cast({:fetch_state}, %ProcessManagerInstance{process_uuid: process_uuid, process_manager_module: process_manager_module} = state) do
  #   state = case EventStore.read_snapshot(process_state_uuid(state)) do
  #     {:ok, snapshot} -> %ProcessManagerInstance{state | process_state: process_manager_module.new(process_uuid, snapshot.data)}
  #     {:error, :snapshot_not_found} -> state
  #   end
  #
  #   {:noreply, state}
  # end
  #
  # defp persist_events(%{pending_events: []} = aggregate_state, _expected_version), do: {:ok, aggregate_state}
  #
  # defp persist_events(%{uuid: aggregate_uuid, pending_events: pending_events} = aggregate_state, expected_version) do
  #   correlation_id = UUID.uuid4
  #   event_data = Mapper.map_to_event_data(pending_events, correlation_id)
  #
  #   :ok = EventStore.append_to_stream(aggregate_uuid, expected_version, event_data)
  #
  #   # clear pending events after appending to stream
  #   {:ok, %{aggregate_state | pending_events: []}}
  # end
  #
  # defp persist_state(%ProcessManagerInstance{process_manager_module: process_manager_module, process_state: process_state} = state) do
  #   :ok = EventStore.record_snapshot(%EventStore.Snapshots.SnapshotData{
  #     source_uuid: process_state_uuid(state),
  #     source_version: 1,
  #     source_type: Atom.to_string(Module.concat(process_manager_module, Container)),
  #     data: process_state.state
  #   })
  # end
  #
  # def get_by_id(id, aggregate, supervisor) do
  #   case :syn.find_by_key(id) do
  #     :undefined ->
  #       load_from_eventstore(id, aggregate, supervisor)
  #     pid ->
  #       IO.inspect "found on cache"
  #       {:ok, pid}
  #   end
  # end
  #
  # # send the 'save' function to aggregate, so save will be done there after receiving
  # # a "process_unsaved_changes" message. Also clean event buffer
  # def save(pid, aggregate) do
  #   saver = fn(id, state, events) ->          # build SAVER anonymous function
  #     {:ok, event_counter} = EventStore.append_events(id, events)
  #     state = %{state | changes: []}          # clen state [fix the __struct__ bug when decode JSON
  #     EventStore.append_snapshot(id, state)   # snapshot state after cleaning event buffer
  #     event_counter + 1                       # returns the counter so it will be stored on state there
  #   end
  #   aggregate.process_unsaved_changes(pid, saver)
  # end
  #
  # #######################
  # # INTERNAL FUNCTIONS  #
  # #######################
  #
  # # without snapshot, we replay from the begining, else, from the snapshot
  # defp load_from_eventstore(id, aggregate, supervisor) do
  #   snapshot = EventStore.load_snapshot(id)
  #   case snapshot do
  #     {:error, _} ->
  #       replay_from_begining(id, aggregate, supervisor)
  #     {:ok, snapshot} ->
  #       replay_events(id, aggregate, supervisor, snapshot)
  #   end
  # end
  #
  # defp replay_from_begining(id, aggregate, supervisor) do
  #   case EventStore.load_events(id) do
  #     {:error, _} ->
  #       :not_found
  #     {:ok, events} ->
  #       {:ok, pid} = supervisor.new
  #       aggregate.load_from_history(pid, events)
  #       {:ok, pid}
  #   end
  # end
  #
  # defp replay_events(id, aggregate, supervisor, snapshot) do
  #   IO.inspect "replaying from snapshot"
  #   position = snapshot.event_counter + 1   # ajust to next event from that snapshot
  #   case EventStore.load_events(id, position) do
  #     {:error, _} ->
  #       :not_found
  #     {:ok, events} ->
  #       {:ok, pid} = supervisor.new
  #       aggregate.load_from_snapshot(pid, events, snapshot)
  #       {:ok, pid}
  #   end
  # end



