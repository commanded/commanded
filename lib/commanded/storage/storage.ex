defmodule Commanded.Storage do
  require Logger
  @moduledoc """
  Proxy API layer to provide a Facade for different data storages, with optimization logic,
  like snapshots, batch reading, etc... 
  The ideia is to read from the config file
  what is the choosen storage, and route the call to the specifc implementation.
  http://elixir-lang.org/docs/stable/elixir/typespecs
  """

  # defaults
  @default_adapter Commanded.Storage.EventStore.Adapter
  @read_event_batch_size 100

  # types
  @type position :: integer
  @type result   :: {position, String.t}
  @type stream   :: String.t
  @type event    :: struct()
  @type events   :: [struct()]



  @doc "Recieve internal event data to append. message building is an adapter task."
  def append_to_stream(stream_id, expected_version, events), do:
    adapter.append_to_stream(stream_id, expected_version, events)


  @doc "Read pure events from stream"
  def read_stream_forward(stream_id, start_version, read_event_batch_size \\ @read_event_batch_size), do:
    adapter.read_stream_forward(stream_id, start_version, read_event_batch_size)


  @doc "Persist process manager state"
  def persist_state(stream_id, version, type, data), do:
    adapter.persist_state(stream_id, version, type, data)

  @doc "Fech state, if not found, returns the same"
  def fetch_state(stream_id, state), do:
    adapter.fetch_state(stream_id, state)


  defp adapter do
    config  = Application.get_env(:commanded, __MODULE__, [])
    config[:adapter] || @default_adapter
  end


  @doc """
  Auto snapshot algorithm. Always snapshot the first existing state, and returns true when the event 
  counter C arrives at the specific position. 
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

