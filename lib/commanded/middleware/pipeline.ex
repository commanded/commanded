defmodule Commanded.Middleware.Pipeline do
  @moduledoc """
  Pipeline is a struct used as an argument in the callback functions of modules
  implementing the `Commanded.Middleware` behaviour.

  This struct must be returned by each function to be used in the next
  middleware based on the configured middleware chain.

  ## Pipeline fields

    - `application` - the Commanded application.
    
    - `assigns` - shared user data as a map.

    - `causation_id` - an optional UUID used to identify the cause of the
       command being dispatched.

    - `correlation_id` - an optional UUID used to correlate related
       commands/events together.

    - `command` - command struct being dispatched.

    - `command_uuid` - UUID assigned to the command being dispatched.

    - `consistency` - requested dispatch consistency, either: `:eventual`
       (default) or `:strong`.

    - `halted` - flag indicating whether the pipeline was halted.

    - `identity` - an atom specifying a field in the command containing the
       aggregate's identity or a one-arity function that returns an identity
       from the command being dispatched.

    - `identity_prefix` - an optional prefix to the aggregate's identity. It may
       be a string (e.g. "prefix-") or a zero arity function
       (e.g. `&MyRouter.identity_prefix/0`).

    - `metadata` - the metadata map to be persisted along with the events.

    - `response` - sets the response to send back to the caller.

  """
  defstruct [
    :application,
    :causation_id,
    :correlation_id,
    :command,
    :command_uuid,
    :consistency,
    :identity,
    :identity_prefix,
    :metadata,
    :response,
    assigns: %{},
    halted: false
  ]

  alias Commanded.Middleware.Pipeline

  @doc """
  Puts the `key` with value equal to `value` into `assigns` map.
  """
  def assign(%Pipeline{} = pipeline, key, value) when is_atom(key) do
    %Pipeline{assigns: assigns} = pipeline

    %Pipeline{pipeline | assigns: Map.put(assigns, key, value)}
  end

  @doc """
  Puts the `key` with value equal to `value` into `metadata` map.

  Note: Use of atom keys in metadata is deprecated in favour of binary strings.
  """
  def assign_metadata(%Pipeline{} = pipeline, key, value) when is_binary(key) or is_atom(key) do
    %Pipeline{metadata: metadata} = pipeline

    %Pipeline{pipeline | metadata: Map.put(metadata, key, value)}
  end

  @doc """
  Has the pipeline been halted?
  """
  def halted?(%Pipeline{halted: halted}), do: halted

  @doc """
  Halts the pipeline by preventing further middleware downstream from being invoked.

  Prevents dispatch of the command if `halt` occurs in a `before_dispatch` callback.
  """
  def halt(%Pipeline{} = pipeline) do
    %Pipeline{pipeline | halted: true} |> respond({:error, :halted})
  end

  @doc """
  Extract the response from the pipeline
  """
  def response(%Pipeline{response: response}), do: response

  @doc """
  Sets the response to be returned to the dispatch caller, unless already set.
  """
  def respond(%Pipeline{response: nil} = pipeline, response) do
    %Pipeline{pipeline | response: response}
  end

  def respond(%Pipeline{} = pipeline, _response), do: pipeline

  @doc """
  Executes the middleware chain.
  """
  def chain(pipeline, stage, middleware)
  def chain(%Pipeline{} = pipeline, _stage, []), do: pipeline
  def chain(%Pipeline{halted: true} = pipeline, :before_dispatch, _middleware), do: pipeline
  def chain(%Pipeline{halted: true} = pipeline, :after_dispatch, _middleware), do: pipeline

  def chain(%Pipeline{} = pipeline, stage, [module | modules]) do
    chain(apply(module, stage, [pipeline]), stage, modules)
  end
end
