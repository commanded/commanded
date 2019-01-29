defmodule Commanded.Commands.DescriberTest do
  use ExUnit.Case, async: false

  alias Commanded.Commands.Describer

  defmodule UnregisteredCommand do
    @moduledoc false
    defstruct [:uuid, :password, :email]
  end

  describe "command describer" do
    test "should not filter anything if not configured" do
      Application.put_env(:commanded, :filter_fields, [])
      uuid = UUID.uuid4()
      cmd = %UnregisteredCommand{uuid: uuid, password: "1234", email: "some@email.testing"}

      assert "%{email: \"some@email.testing\", password: \"1234\", uuid: \"#{uuid}\"}" == Describer.describe(cmd)
    end

    test "should filter password" do
      Application.put_env(:commanded, :filter_fields, [:password])
      uuid = UUID.uuid4()
      cmd = %UnregisteredCommand{uuid: uuid, password: "1234", email: "some@email.testing"}

      assert "%{email: \"some@email.testing\", password: \"[FILTERED]\", uuid: \"#{uuid}\"}" == Describer.describe(cmd)
    end

    test "should filter password and email" do
      Application.put_env(:commanded, :filter_fields, [:password, :email])
      uuid = UUID.uuid4()
      cmd = %UnregisteredCommand{uuid: uuid, password: "1234", email: "some@email.testing"}

      assert "%{email: \"[FILTERED]\", password: \"[FILTERED]\", uuid: \"#{uuid}\"}" == Describer.describe(cmd)
    end
  end
end
