defmodule Commanded.Config do
  @moduledoc """
  This module handles fetching values from the config with some additional niceties
  """

  @doc """
  Fetches a value from the config, or from the environment if {:system, "VAR"}
  or {:system, "VAR", "default-value"} is provided as a config value.
  """

  @spec get(atom, atom) :: term
  def get(app, key) when is_atom(app) and is_atom(key) do
    normalize Application.get_env(app, key)
  end

  @spec get(atom, atom, atom) :: term
  def get(app, key1, key2) when is_atom(app) and is_atom(key1) and is_atom(key2) do
    case Application.get_env(app, key1) do
      nil -> nil
      val -> normalize val[key2]
    end
  end

  defp normalize(list) when is_list(list) do
    Enum.map(list, fn(elem) ->
      case elem do
	{key, {:system, _, _}=val} -> {key, normalize(val)}
	{key, {:system, _}=val} -> {key, normalize(val)}
	val -> val
      end
    end)
  end

  defp normalize(val) do
    case val do
      {:system, env_var} ->
        System.get_env(env_var)
      {:system, env_var, preconfigured_default} ->
        case System.get_env(env_var) do
          nil -> preconfigured_default
          val -> val
        end
      val ->
        val
    end
  end

end
