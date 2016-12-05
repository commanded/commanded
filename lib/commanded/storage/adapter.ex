defmodule Commanded.Storage.Adapter do
  @moduledoc """
  Implement this functions below to add a new data storage for your events and snapshots.
  The persistence modules will retreive a pure list of events, ready for replay, instead of
  dealing with localized messages. It's an adapter responsability to filter and answer only the
  necessary data to be used inside Commanded
  """

  @type stream            :: String.t     # The Stream ID
  @type position          :: integer      # From which position we start reading the stream
  @type events            :: [struct()]   # TODO: implement common data strucutre 
  @type event_data        :: [struct()]
  @type batch             :: [struct()]
  @type expected_version  :: number
  @type stream_id         :: String.t
  @type state             :: struct()
  @type reason            :: atom
  @type snapshot          :: struct()
  @type start_pos         :: position     # When appending many events, the start position we got
  @type end_pos           :: position     # When appending many events, the last position we got
  @type read_event_batch_size  :: number
  @type start_version          :: number
  @type type              :: atom
  @type version           :: number


  ### Events

  # @doc "Load a list of events from an specific position"
  # @callback load_events(stream, position)      :: {:ok, events}  |  {:error, reason}
  #
  # @doc "Load a all list of events from an specific position"
  # @callback load_all_events(stream)            :: {:ok, events}  |  {:error, reason}
  @doc "Load a batch of events from storage"
  @callback read_stream_forward(stream_id, start_version, read_event_batch_size) :: {:ok, batch} | {:error, reason}

  @doc "Load a list of events from an specific position"
  @callback append_to_stream(stream_id, expected_version, event_data) :: :ok | {:error, reason}

  @doc "Persist a state snapshot"
  @callback persist_state(stream_id, version, type, module, state)  :: :ok  | {:error, reason}


  ### Snapshots

  # @doc "Load a snapshot"
  # @callback load_snapshot(stream)           :: {:ok, state}    |  {:error, reason}
  #
  # @doc "Load a list of events from an specific position"
  # @callback append_snapshot(stream, state)  :: {:ok, position} |  {:error, reason}


  ### Features

  # @doc "Snapshot optimization support for building the state"
  # @callback snapshot_optimization_support() ::  true  |  false
  #
  # @doc "Batch reading optimization support"
  # @callback batch_support()                 ::  true  |  false

end
