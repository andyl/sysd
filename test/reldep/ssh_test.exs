defmodule RelDep.SSHTest do
  use ExUnit.Case

  test "SSH.Error is a proper exception" do
    error = %RelDep.SSH.Error{message: "test error"}
    assert Exception.message(error) == "test error"
  end
end
