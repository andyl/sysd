defmodule Mix.Tasks.RelmanTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "mix relman prints help text" do
    output = capture_io(fn -> Mix.Tasks.Relman.run([]) end)
    assert output =~ "Relman - Deploy Elixir releases"
    assert output =~ "mix relman.init"
    assert output =~ "mix relman.deploy"
    assert output =~ "mix relman.rollback"
    assert output =~ "mix relman.cleanup"
  end
end
