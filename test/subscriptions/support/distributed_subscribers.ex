defmodule Commanded.Subscriptions.DistributedSubscribers do
  import ExUnit.Assertions

  alias Commanded.DistributedApp
  alias Commanded.Subscriptions

  @event_handlers [EventHandler1, EventHandler2, EventHandler3]
  @process_managers [ProcessManager1, ProcessManager2, ProcessManager3]

  for event_handler <- @event_handlers do
    defmodule event_handler do
      use Commanded.Event.Handler,
        application: DistributedApp,
        name: __MODULE__,
        consistency: :strong
    end
  end

  for process_manager <- @process_managers do
    defmodule process_manager do
      use Commanded.ProcessManagers.ProcessManager,
        application: DistributedApp,
        name: __MODULE__,
        consistency: :strong
    end
  end

  def all, do: @event_handlers ++ @process_managers

  def start_subscribers(nodes) do
    reply_to = self()

    for node <- nodes do
      Node.spawn_link(node, fn ->
        Logger.configure(level: :error)

        {:ok, _pid} = DistributedApp.start_link()

        for subscriber <- Enum.shuffle(all()) do
          {:ok, _pid} = subscriber.start_link()

          # Sleep to allow subscribers to be distributed amongst all nodes
          :timer.sleep(100)
        end

        send(reply_to, {:started, node})

        :timer.sleep(:infinity)
      end)
    end

    for node <- nodes do
      assert_receive {:started, ^node}, 5_000
    end
  end

  def query_subscriptions(nodes) do
    reply_to = self()

    for node <- nodes do
      Node.spawn_link(node, fn ->
        subscriptions =
          Subscriptions.all(DistributedApp)
          |> Enum.map(fn {name, _module, _pid} -> name end)
          |> Enum.sort()

        send(reply_to, {:subscriptions, node, subscriptions})
      end)
    end
  end
end
