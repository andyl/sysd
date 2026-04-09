defmodule Mix.Tasks.RelDepTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "mix reldep prints help text" do
    output = capture_io(fn -> Mix.Tasks.Reldep.run([]) end)
    assert output =~ "RelDep - Deploy Elixir releases"
    assert output =~ "mix reldep.init"
    assert output =~ "mix reldep.release"
    assert output =~ "mix reldep.deploy"
    assert output =~ "mix reldep.rollback"
    assert output =~ "mix reldep.cleanup"
  end
end
