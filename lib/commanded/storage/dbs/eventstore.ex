defmodule Commanded.Storage.Dbs.Eventstore do
  require Logger
  alias Extreme.Messages.ReadEventCompleted
  @event_store     Engine.EventStore
  @snapshot        "-SNAPSHOT"                             # to namespace the snapshot stream
  #@snapshot_period Engine.Settings.get(:snapshot_period)
  @moduledoc """ 
  Interface with the Extreme EventStore driver to save and read to EVENTSTORE.
  Note that the Engine supervisor starts the driver naming it as 'EventStore'.
  iex> Engine.EventStore.save_event("people",%Obligation.Event.MoneyDeposited{})
  This Eventstore interface is intelligent when saving snapshots
  """

  @doc "Save a list of events to the stream."
  def append_events(stream, events) do
    Engine.Messages.write_events(stream, events)
      |> send_to_eventstore
      |> extract_event_numbers
  end

  @doc "Load all events for that stream"
  def load_all_events(stream) do
    Engine.Messages.read_events(stream)
      |> send_to_eventstore
      |> extract_events
  end

  @doc "Load events, but from a specific position"
  def load_events(stream, position) do
    Engine.Messages.read_events(stream, position)
      |> send_to_eventstore
      |> extract_events
  end


  @doc "snapshot adding -snapshot to its stream name"
  def append_snapshot(stream, state) do
    Engine.Messages.write_events(stream <> @snapshot, [state])
      |> send_to_eventstore
      |> extract_event_numbers
  end

  @doc "Load the last snapshot for that stream"
  def load_snapshot(stream) do
    Engine.Messages.read_event_backward(stream <> @snapshot)
      |> send_to_eventstore
      |> extract_snapshot
  end

  ###############
  ## PRIVATES  ##
  ###############
  defp extract_snapshot({:ok, response}), do: {:ok, response.events |> List.last |> extract_data}
  defp extract_snapshot({:error,_}),      do: {:error, :not_found}
  defp extract_snapshot({:error,_,_}),    do: {:error, :not_found}

  defp extract_events({:ok, response}),   do: {:ok, Enum.map(response.events, &extract_data/1)}
  defp extract_events({:error,_}),        do: {:error, :not_found}
  defp extract_events({:error,_,_}),      do: {:error, :not_found}

  # Example of response when writing 4 events from position 5
  # %Extreme.Messages.WriteEventsCompleted{commit_position: 71391498,
  # first_event_number: 5, last_event_number: 9, message: nil,
  # prepare_position: 71391498, result: :Success}

  defp format_response({:ok, reponse}),    do: {:ok, reponse}
  defp extract_event_numbers({:ok, res}),  do: {:ok, [res.first_event_number, res.last_event_number]}
  defp extract_event_numbers({:error, reason}), do: {:error, reason}

  # rebuild the struct from a string stored in the eventstore
  defp extract_data(message) do
    st = message.event.event_type |> make_alias |> struct
    message.event.data |> deserialize(st)
  end

  defp deserialize(data, struct \\ nil),
    do: Engine.Storage.Serializer.decode(data, struct)
    #do: :erlang.binary_to_term(data)
    # do: Poison.decode!(data)

  # partially applying Extreme.execute, so you can use this func with pipe operators
  defp send_to_eventstore(message),
    do: Extreme.execute(@event_store, message)

  # transforms a ":Jim" string into a Jim atom alias
  def make_alias(name) do
    name_s = String.to_atom(name)
    ast = {:__aliases__, [alias: false], [name_s]}
    {result, _} = Code.eval_quoted(ast)
    result
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
