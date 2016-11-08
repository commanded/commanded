defmodule Commanded.Commands.Middleware.MiddlewareTest do
  use Commanded.StorageCase

  import Commanded.Enumerable

  alias Commanded.Helpers.CommandAuditMiddleware

  defmodule IncrementCount do
    defstruct aggregate_uuid: nil, by: 1
  end

  defmodule Fail do
    defstruct aggregate_uuid: nil
  end

  defmodule CountIncremented do
    defstruct [:count]
  end

  defmodule CounterAggregateRoot do
    use EventSourced.AggregateRoot, fields: [count: 0]

    def increment(%CounterAggregateRoot{state: %{count: count}} = counter, increment_by) when is_integer(increment_by) do
      {:ok, update(counter, %CountIncremented{count: count + increment_by})}
    end

    def apply(%CounterAggregateRoot.State{} = state, %CountIncremented{count: count}) do
      %CounterAggregateRoot.State{state | count: count}
    end
  end

  defmodule CommandHandler do
    @behaviour Commanded.Commands.Handler

    def handle(%CounterAggregateRoot{} = aggregate, %IncrementCount{by: by}) do
      CounterAggregateRoot.increment(aggregate, by)
    end
  end

  defmodule FirstMiddleware do
    @behaviour Commanded.Middleware

    def before_dispatch(pipeline), do: pipeline
    def after_dispatch(pipeline), do: pipeline
    def after_failure(pipeline), do: pipeline
  end

  defmodule LastMiddleware do
    @behaviour Commanded.Middleware

    def before_dispatch(pipeline), do: pipeline
    def after_dispatch(pipeline), do: pipeline
    def after_failure(pipeline), do: pipeline
  end

  defmodule Router do
    use Commanded.Commands.Router

    middleware FirstMiddleware
    middleware CommandAuditMiddleware
    middleware LastMiddleware

    dispatch IncrementCount, to: CommandHandler, aggregate: CounterAggregateRoot, identity: :aggregate_uuid
  end

  @tag :wip
  test "should call middleware for each command dispatch" do
    aggregate_uuid = UUID.uuid4

    {:ok, _} = CommandAuditMiddleware.start_link

    :ok = Router.dispatch(%IncrementCount{aggregate_uuid: aggregate_uuid, by: 1})
    :ok = Router.dispatch(%IncrementCount{aggregate_uuid: aggregate_uuid, by: 2})
    :ok = Router.dispatch(%IncrementCount{aggregate_uuid: aggregate_uuid, by: 3})

    dispatched_commands = CommandAuditMiddleware.dispatched_commands
    succeeded_commands = CommandAuditMiddleware.succeeded_commands
    failed_commands = CommandAuditMiddleware.failed_commands

    assert length(dispatched_commands) == 3
    assert length(succeeded_commands) == 3
    assert length(failed_commands) == 0
    assert pluck(dispatched_commands, :by) == [1, 2, 3]
    assert pluck(succeeded_commands, :by) == [1, 2, 3]
  end
end
