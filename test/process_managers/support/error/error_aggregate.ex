defmodule Commanded.ProcessManagers.ErrorAggregate do
  @moduledoc false
  defstruct [:process_uuid]

  defmodule Commands do
    defmodule(StartProcess, do: defstruct([:process_uuid, :strategy, :delay, :reply_to]))
    defmodule(RaiseError, do: defstruct([:process_uuid, :message, :reply_to]))
    defmodule(RaiseException, do: defstruct([:process_uuid, :message, :reply_to]))
    defmodule(AttemptProcess, do: defstruct([:process_uuid, :strategy, :delay, :reply_to]))
    defmodule(ContinueProcess, do: defstruct([:process_uuid, :reply_to]))
  end

  defmodule Events do
    defmodule(ProcessStarted, do: defstruct([:process_uuid, :strategy, :delay, :reply_to]))
    defmodule(ProcessContinued, do: defstruct([:process_uuid, :reply_to]))
    defmodule(ProcessError, do: defstruct([:process_uuid, :message, :reply_to]))
    defmodule(ProcessException, do: defstruct([:process_uuid, :message, :reply_to]))
  end

  alias Commanded.ProcessManagers.ErrorAggregate
  alias Commands.{AttemptProcess, ContinueProcess, RaiseError, RaiseException, StartProcess}
  alias Events.{ProcessContinued, ProcessError, ProcessException, ProcessStarted}

  def execute(%ErrorAggregate{}, %StartProcess{} = command) do
    %StartProcess{
      process_uuid: process_uuid,
      strategy: strategy,
      delay: delay,
      reply_to: reply_to
    } = command

    %ProcessStarted{
      process_uuid: process_uuid,
      strategy: strategy,
      delay: delay,
      reply_to: reply_to
    }
  end

  def execute(%ErrorAggregate{}, %RaiseError{} = command) do
    %RaiseError{process_uuid: process_uuid, message: message, reply_to: reply_to} = command

    %ProcessError{process_uuid: process_uuid, message: message, reply_to: reply_to}
  end

  def execute(%ErrorAggregate{}, %RaiseException{} = command) do
    %RaiseException{process_uuid: process_uuid, message: message, reply_to: reply_to} = command

    %ProcessException{process_uuid: process_uuid, message: message, reply_to: reply_to}
  end

  def execute(%ErrorAggregate{}, %AttemptProcess{}),
    do: {:error, :failed}

  def execute(%ErrorAggregate{}, %ContinueProcess{process_uuid: process_uuid, reply_to: reply_to}),
    do: %ProcessContinued{process_uuid: process_uuid, reply_to: reply_to}

  def apply(%ErrorAggregate{} = aggregate, %ProcessStarted{process_uuid: process_uuid}),
    do: %ErrorAggregate{aggregate | process_uuid: process_uuid}

  def apply(%ErrorAggregate{} = aggregate, _event), do: aggregate
end
