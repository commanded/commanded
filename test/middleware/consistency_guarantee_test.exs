defmodule Commanded.Middleware.ConsistencyGuaranteeTest do
  use ExUnit.Case

  alias Commanded.DefaultApp
  alias Commanded.Event.Handler
  alias Commanded.Middleware.ConsistencyGuarantee
  alias Commanded.Middleware.Pipeline
  alias Commanded.Subscriptions

  describe "command dispatched by a strongly consistent event handler" do
    setup do
      start_supervised!({DefaultApp, name: :app1})
      start_supervised!({DefaultApp, name: :app2})

      # Subscription registered with a proxy process, not the handler itself
      proxy = start_supervised!({Task, fn -> Process.sleep(:infinity) end})

      :ok = Subscriptions.register(:app1, "handler", ExampleHandler, proxy, :strong)
      :ok = Subscriptions.register(:app2, "handler", ExampleHandler, proxy, :strong)

      :ok = Handler.put_handler_identity(:app1, "handler")

      :ok
    end

    test "should not wait for the handler dispatching the command" do
      assert await_consistency(:app1) == nil
    end

    test "should wait for a handler of another application with the same name" do
      assert await_consistency(:app2) == {:error, :consistency_timeout}
    end
  end

  defp await_consistency(application) do
    pipeline = %Pipeline{
      application: application,
      consistency: :strong,
      assigns: %{aggregate_uuid: "stream1", aggregate_version: 1}
    }

    pipeline
    |> ConsistencyGuarantee.before_dispatch()
    |> ConsistencyGuarantee.after_dispatch()
    |> Pipeline.response()
  end
end
