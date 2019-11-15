defmodule Commanded.AggregateCase do
  @moduledoc """
  This module defines the test case to be used by aggregate tests.
  """

  use ExUnit.CaseTemplate

  using aggregate: aggregate do
    quote bind_quoted: [aggregate: aggregate] do
      @aggregate_module aggregate

      # Assert that the expected events are returned when the given commands have been executed
      defp assert_events(commands, expected_events) do
        assert_events([], commands, expected_events)
      end

      defp assert_events(initial_events, commands, expected_events) do
        {_aggregate, events, error} = aggregate_run(initial_events, commands)

        actual_events = List.wrap(events)

        assert is_nil(error)
        assert actual_events == expected_events
      end

      # Assert that the aggregate will have the expected_state after the given commands have been executed
      defp assert_state(commands, expected_state) do
        assert_state([], commands, expected_state)
      end

      defp assert_state(initial_events, commands, expected_state) do
        {aggregate, events, error} = aggregate_run(initial_events, commands)
        assert is_nil(error)
        assert aggregate == expected_state
      end

      defp assert_error(commands, expected_error) do
        assert_error([], commands, expected_error)
      end

      defp assert_error(initial_events, commands, expected_error) do
        {_aggregate, _events, error} = aggregate_run(initial_events, commands)
        assert error == expected_error
      end

      # Apply the given commands to the aggregate hydrated with the given initial_events
      defp aggregate_run(initial_events, commands) do
        %@aggregate_module{}
        |> evolve(initial_events)
        |> execute(commands)
      end

      # Execute one or more commands against an aggregate
      defp execute(aggregate, commands) do
        commands
        |> List.wrap()
        |> Enum.reduce({aggregate, [], nil}, fn
          command, {aggregate, _events, nil} ->
            case @aggregate_module.execute(aggregate, command) do
              {:error, reason} = error -> {aggregate, nil, error}
              events -> {evolve(aggregate, events), events, nil}
            end

          _command, {aggregate, _events, _error} = reply ->
            reply
        end)
      end

      # Apply the given events to the aggregate state
      defp evolve(aggregate, events) do
        events
        |> List.wrap()
        |> Enum.reduce(aggregate, &@aggregate_module.apply(&2, &1))
      end
    end
  end
end
