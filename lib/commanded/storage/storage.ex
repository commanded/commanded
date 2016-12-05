defmodule Commanded.Storage.Storage do
  require Logger
  #@snapshot_period 3
  #@storage Commanded.Settings.get(:storage)   # can be Eventstore or Postgres
  @moduledoc """
  Proxy API layer to provide a Facade for different data storages, with optimization logic,
  like snapshots, batch reading, etc... 
  The ideia is to read from the config file
  what is the choosen storage, and route the call to the specifc implementation.
  http://elixir-lang.org/docs/stable/elixir/typespecs
  """
  # defaults
  @default_adapter Commanded.Storage.Postgre.Adapter
  @read_event_batch_size 100

  # types
  @type position :: integer
  @type result   :: {position, String.t}
  @type stream   :: String.t
  @type event    :: struct()
  @type events   :: [struct()]

  # specs
  @spec which_storage?() :: atom
  @spec append_event(stream, event)   :: any()
  @spec append_events(stream, events) :: any()






  @doc "Recieve internal event data to append. message building is an adapter task."
  def append_to_stream(stream_id, expected_version, events) do
    config  = Application.get_env(:commanded, __MODULE__, [])
    adapter = config[:adapter] || @default_adapter
    adapter.append_to_stream(stream_id, expected_version, events)
  end




  @doc "If you want to know what storage is configured"
  def which_storage?(), do: @storage

  @doc "Save only one event to the stream."
  def append_event(stream, event), do:
    @storage.append_event(stream, event)

  @doc "Save a list of events to the stream."
  def append_events(stream, events), do:
    @storage.append_events(stream, events)

  @doc "Load all events for that stream"
  def load_all_events(stream), do:
    @storage.load_all_events(stream)

  @doc "Load events, but from a specific position"
  def load_events(stream, position), do:
    @storage.load_events(stream, position)

  @doc "Save snapshot after checking the frequency config, adding -snapshot to its namespace"
  def append_snapshot(stream, state), do:
    @storage.append_snapshot(stream, state)

  @doc "Load the last snapshot for that stream"
  def load_snapshot(stream), do:
    @storage.load_snapshot(stream)



  @doc """
  Always snapshot the first existing state, and returns true when the event counter C arrives 
  at the specific position. 
  """
  defp mod(0,p),             do: true    # we snapshot the state from the first event
  defp mod(c,p) when c  < p, do: false
  defp mod(c,p) when c >= p  do
    case rem c,p do
      0 -> true
      _ -> false
    end
  end


end

