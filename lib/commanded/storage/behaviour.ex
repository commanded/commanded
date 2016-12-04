defmodule Commanded.Storage.Adapter do
  @moduledoc """
  Implement this functions below to add a new data storage for your events and snapshots. Consider this as the most
  low level layer to communicate with the dbs layers. When you implement your db layer, try to send at least some value
  if you don't support position, batch, etc... Sometimes your db lacks loading from a specific position [needed for batch],
  or snapshooting, so implement this feedback also, and the system will deal automatically. If position reading is not
  supported, the persistence.ex will use the load_all_events instead.
  Auto-snapshotting should be implemented as a separate feature from the storage abstraction. Since snapshotting can 
  be run as a background activity. Completely separate from persisting events for an aggregate. This also ensures that 
  there won't be increased latency on aggregate operations because a snapshot is also being recorded.
  """

  @type stream      :: String.t             # The Stream ID
  @type position    :: integer              # From which position we start reading the stream
  @type events      :: [struct()]           # Your incredible event list   TODO: implement common data strucutre for all dbs
  @type state       :: struct()
  @type reason      :: atom
  @type snapshot    :: struct()
  @type start_pos   :: position             # When appending many events, the start position we got
  @type end_pos     :: position             # When appending many events, the last position we got


  ### Events

  @doc "Load a list of events from an specific position"
  @callback load_events(stream, position)      :: {:ok, events}  |  {:error, reason}

  @doc "Load a all list of events from an specific position"
  @callback load_all_events(stream)            :: {:ok, events}  |  {:error, reason}

  @doc "Load a list of events from an specific position"
  @callback append_events(stream, events)      :: {:ok, {start_pos, end_pos}}  |  {:error, reason}


  ### Snapshots

  @doc "Load a snapshot"
  @callback load_snapshot(stream)           :: {:ok, state}    |  {:error, reason}

  @doc "Load a list of events from an specific position"
  @callback append_snapshot(stream, state)  :: {:ok, position} |  {:error, reason}


  ### Features

  @doc "Snapshot optimization support for building the state"
  @callback snapshot_optimization_support() ::  true  |  false

  @doc "Batch reading optimization support"
  @callback batch_support()                 ::  true  |  false

end
