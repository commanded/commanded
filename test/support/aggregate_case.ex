defmodule Commanded.AggregateCase do
  @moduledoc """
  This module defines the test case to be used by aggregate tests.
  """

  use ExUnit.CaseTemplate

  alias Commanded.Aggregate.Multi

  using opts do
    quote do
      @aggregate Keyword.fetch!(unquote(opts), :aggregate)

      # Assert that the expected events are returned when the given commands have been executed
      defp assert_events(commands, expected_events) do
        assert_events([], commands, expected_events)
      end

      defp assert_events(initial_events, commands, expected_events) do
        assert {:ok, _state, events} = aggregate_run(initial_events, commands)

        actual_events = List.wrap(events)
        expected_events = List.wrap(expected_events)

        assert actual_events == expected_events
      end

      # Assert that the aggregate will have the expected_state after the given commands have been executed
      defp assert_state(commands, expected_state) do
        assert_state([], commands, expected_state)
      end

      defp assert_state(initial_events, commands, expected_state) do
        assert {:ok, state, events} = aggregate_run(initial_events, commands)
        assert state == expected_state
      end

      defp assert_error(commands, expected_error) do
        assert_error([], commands, expected_error)
      end

      defp assert_error(initial_events, commands, expected_error) do
        assert ^expected_error = aggregate_run(initial_events, commands)
      end

      # Apply the given commands to the aggregate hydrated with the given initial_events
      defp aggregate_run(initial_events, commands) do
        @aggregate
        |> struct()
        |> evolve(initial_events)
        |> execute(commands)
      end

      # Execute one or more commands against an aggregate.
      defp execute(state, commands) do
        try do
          {state, events} =
            commands
            |> List.wrap()
            |> Enum.reduce({state, []}, fn command, {state, events} ->
              case @aggregate.execute(state, command) do
                {:error, _error} = error ->
                  throw(error)

                %Multi{} = multi ->
                  case Multi.run(multi) do
                    {:error, _reason} = error ->
                      throw(error)

                    {state, new_events} ->
                      {state, events ++ new_events}
                  end

                none when none in [:ok, nil, []] ->
                  {state, events}

                {:ok, new_events} ->
                  {evolve(state, new_events), events ++ List.wrap(new_events)}

                new_events when is_list(new_events) ->
                  {evolve(state, new_events), events ++ new_events}

                new_event when is_map(new_event) ->
                  {evolve(state, new_event), events ++ [new_event]}

                invalid ->
                  flunk("unexpected: " <> inspect(invalid))
              end
            end)

          {:ok, state, events}
        catch
          {:error, _error} = reply -> reply
        end
      end

      # Apply the given events to the aggregate state
      defp evolve(state, events) do
        events
        |> List.wrap()
        |> Enum.reduce(state, &@aggregate.apply(&2, &1))
      end
    end
  end
end
