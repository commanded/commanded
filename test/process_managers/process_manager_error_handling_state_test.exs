defmodule Commanded.ProcessManager.ProcessManagerErrorHandlingStateTest do
  use ExUnit.Case

  alias Commanded.ProcessManagers.ErrorAggregate.Commands.{AttemptProcess, StartProcess}
  alias Commanded.ProcessManagers.ErrorAggregate.Events.ProcessStarted

  alias Commanded.ProcessManagers.{
    ErrorApp,
    ErrorRouter,
    FailureContext,
    StateErrorHandlingProcessManager
  }

  alias Commanded.EventStore.RecordedEvent
  alias Commanded.UUID

  setup do
    start_supervised!(ErrorApp)
    start_supervised!(StateErrorHandlingProcessManager)

    :ok
  end

  test "should receive the process instance state in the context" do
    process_uuid = UUID.uuid4()
    reply_to = reply_to()

    command = %StartProcess{process_uuid: process_uuid, reply_to: reply_to}

    assert :ok = ErrorRouter.dispatch(command, application: ErrorApp)

    assert_receive {:error, :failed, failed_command, failure_context}

    assert match?(%AttemptProcess{process_uuid: ^process_uuid}, failed_command)

    assert match?(
             %FailureContext{
               enriched_metadata: %{
                 application: ErrorApp,
                 causation_id: _causation_id,
                 correlation_id: _correlation_id,
                 created_at: %DateTime{},
                 event_id: _event_id,
                 event_number: _event_number,
                 stream_id: _stream_id,
                 stream_version: _stream_version
               },
               last_event: %RecordedEvent{
                 data: %ProcessStarted{
                   process_uuid: ^process_uuid,
                   reply_to: ^reply_to
                 }
               },
               process_manager_state: %StateErrorHandlingProcessManager{
                 process_uuid: ^process_uuid,
                 reply_to: ^reply_to
               },
               stacktrace: nil,
               context: %{},
               pending_commands: []
             },
             failure_context
           )
  end

  defp reply_to, do: :erlang.pid_to_list(self())
end
