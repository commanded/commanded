defmodule Commanded.PubSub.Adapter do
  @moduledoc """
  Pub/sub behaviour for use by Commanded to subscribe to and broadcast messages.
  """

  @type adapter_meta :: map
  @type application :: Commanded.Application.t()

  @doc """
  Return an optional supervisor spec for pub/sub.
  """
  @callback child_spec(application, config :: Keyword.t()) ::
              {:ok, [:supervisor.child_spec() | {module, term} | module], adapter_meta}

  @doc """
  Subscribes the caller to the PubSub adapter's topic.
  """
  @callback subscribe(adapter_meta, topic :: String.t()) :: :ok | {:error, term}

  @doc """
  Broadcasts message on given topic.

    * `topic` - The topic to broadcast to, ie: `"users:123"`
    * `message` - The payload of the broadcast

  """
  @callback broadcast(adapter_meta, topic :: String.t(), message :: term) :: :ok | {:error, term}

  @doc """
  Track the current process under the given `topic`, uniquely identified by
  `key`.
  """
  @callback track(adapter_meta, topic :: String.t(), key :: term) :: :ok | {:error, term}

  @doc """
  List tracked PIDs for a given topic.
  """
  @callback list(adapter_meta, topic :: String.t()) :: [{term, pid}]
end
