
defmodule Commanded.Serialization.JsonSerializer.EventName do

  alias Commanded.Serialization.JsonSerializer.EventNameMapper
  alias Commanded.Serialization.JsonSerializer.EventNameMapper.EventNames

  defmacro __using__(event_name) do
    mapping = {:"#{event_name}", __CALLER__.module}
    event_names =
      case :erlang.get(EventNames) do
	:undefined -> [mapping]
	ev_names -> [mapping | ev_names]
      end
    
    :erlang.put(EventNames, event_names)
    
    quote do
      event_names = unquote(event_names)
      
      content = quote do
	Module.register_attribute __MODULE__, :event_names, accumulate: true
	
	for ev_name <- unquote(event_names) do
	    @event_names ev_name
	end

	def to_name(module) do
	  case Enum.find(@event_names, &(module == elem(&1, 1))) do
	    nil -> nil
	    entry -> to_string(elem(entry, 0))
	  end
	end
	def to_type(event_name), do: Keyword.get(@event_names, :"#{event_name}")
      end

      ignore_module_conflict = Code.compiler_options[:ignore_module_conflict]
      Code.compiler_options(ignore_module_conflict: true)
      Module.create(EventNameMapper, content, Macro.Env.location(__ENV__))
      Code.compiler_options(ignore_module_conflict: ignore_module_conflict)
    end
  end
end

defmodule Commanded.Serialization.JsonSerializer do
  
  @moduledoc """
  A serializer that uses the JSON format.
  """

  @behaviour Commanded.EventStore.Serializer

  alias Commanded.Serialization.JsonDecoder
  alias Commanded.Serialization.JsonSerializer.EventNameMapper

  defp event_mapper_to_name(module) do
    if Code.ensure_loaded?(EventNameMapper) do
      apply(EventNameMapper, :to_name, [module])
    else
      nil
    end
  end

  defp event_mapper_to_type(event_name) do
    if Code.ensure_loaded?(EventNameMapper) do
      apply(EventNameMapper, :to_type, [event_name])
    else
      nil
    end
  end

  def to_event_name(module) do
    event_mapper_to_name(module) || Atom.to_string(module)
  end

  defp to_event_type(event_name) do
    (event_mapper_to_type(event_name) || event_name |> String.to_existing_atom) |> struct
  end

  @doc """
  Serialize given term to JSON binary data.
  """
  def serialize(term) do
    Poison.encode!(term)
  end

  @doc """
  Deserialize given JSON binary data to the expected type.
  """
  def deserialize(binary, config) do
    type = case Keyword.get(config, :type, nil) do
      nil -> nil
      type -> to_event_type(type)
    end

    binary
    |> Poison.decode!(as: type)
    |> JsonDecoder.decode
  end
end
