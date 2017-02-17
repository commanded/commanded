defmodule Commanded.Serialization.JsonSerializerTest do
  use ExUnit.Case

  alias Commanded.Config

  test "should read config values" do
    assert nil == Config.get :commanded, :no_key
    assert nil == Config.get :commanded, :no_key1, :no_key2
    
    Application.put_env :commanded, :key, :value
    assert :value == Config.get :commanded, :key

    Application.put_env :commanded, :key, [sub_key1: :sub_val1, sub_key2: :sub_val2]
    assert :sub_val1 == Config.get :commanded, :key, :sub_key1
    assert :sub_val2 == Config.get :commanded, :key, :sub_key2

    Application.put_env :commanded, :key, {:system, "KEY"}
    assert nil == Config.get :commanded, :key

    Application.put_env :commanded, :key, {:system, "KEY", :default_val}
    assert :default_val == Config.get :commanded, :key

    Application.put_env :commanded, :key, {:system, "KEY"}
    System.put_env "KEY", "val"
    assert "val" == Config.get :commanded, :key

    Application.put_env :commanded, :key, [
      sub_key1: {:system, "SUB_KEY1"},
      sub_key2: {:system, "SUB_KEY2", :sub_key2_default},
    ]
    assert nil == Config.get :commanded, :key, :sub_key1
    assert :sub_key2_default == Config.get :commanded, :key, :sub_key2

    Application.put_env :commanded, :key, [
      sub_key1: {:system, "SUB_KEY1"},
      sub_key2: {:system, "SUB_KEY2", :sub_key2_default},
    ]
    System.put_env "SUB_KEY1", "sub-val-1"
    System.put_env "SUB_KEY2", "sub-val-2"
    assert "sub-val-1" == Config.get :commanded, :key, :sub_key1
    assert "sub-val-2" == Config.get :commanded, :key, :sub_key2

  end

end
