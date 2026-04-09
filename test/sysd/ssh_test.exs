defmodule Sysd.SSHTest do
  use ExUnit.Case

  test "SSH.Error is a proper exception" do
    error = %Sysd.SSH.Error{message: "test error"}
    assert Exception.message(error) == "test error"
  end
end
