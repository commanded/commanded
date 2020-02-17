defmodule Commanded.ProcessManagers.ErrorAggregate do
  @moduledoc false
  @derive Jason.Encoder
  defstruct [:process_uuid]

  defmodule Commands do
    defmodule StartProcess do
      @derive Jason.Encoder
      defstruct [:process_uuid, :strategy, :delay, :reply_to]
    end

    defmodule RaiseError do
      @derive Jason.Encoder
      defstruct [:process_uuid, :message, :reply_to]
    end

    defmodule RaiseException do
      @derive Jason.Encoder
      defstruct [:process_uuid, :message, :reply_to]
    end

    defmodule AttemptProcess do
      @derive Jason.Encoder
      defstruct [:process_uuid, :strategy, :delay, :reply_to]
    end

    defmodule ContinueProcess do
      @derive Jason.Encoder
      defstruct [:process_uuid, :reply_to]
    end
  end

  defmodule Events do
    defmodule ProcessStarted do
      @derive Jason.Encoder
      defstruct [:process_uuid, :strategy, :delay, :reply_to]
    end

    defmodule ProcessContinued do
      @derive Jason.Encoder
      defstruct [:process_uuid, :reply_to]
    end

    defmodule ProcessError do
      @derive Jason.Encoder
      defstruct [:process_uuid, :message, :reply_to]
    end

    defmodule ProcessException do
      @derive Jason.Encoder
      defstruct [:process_uuid, :message, :reply_to]
    end

    defmodule ProcessDispatchException do
      @derive Jason.Encoder
      defstruct [:process_uuid, :message, :reply_to]
    end
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
    %RaiseError{message: message} = command

    {:error, message}
  end

  def execute(%ErrorAggregate{}, %RaiseException{} = command) do
    %RaiseException{message: message} = command

    raise message
  end

  def execute(%ErrorAggregate{}, %AttemptProcess{}),
    do: {:error, :failed}

  def execute(%ErrorAggregate{}, %ContinueProcess{process_uuid: process_uuid, reply_to: reply_to}),
    do: %ProcessContinued{process_uuid: process_uuid, reply_to: reply_to}

  def apply(%ErrorAggregate{} = aggregate, %ProcessStarted{process_uuid: process_uuid}),
    do: %ErrorAggregate{aggregate | process_uuid: process_uuid}

  def apply(%ErrorAggregate{} = aggregate, _event), do: aggregate
end
