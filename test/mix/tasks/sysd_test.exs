defmodule Mix.Tasks.SysdTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "mix sysd prints help text" do
    output = capture_io(fn -> Mix.Tasks.Sysd.run([]) end)
    assert output =~ "Sysd - Deploy Elixir releases"
    assert output =~ "mix sysd.init"
    assert output =~ "mix sysd.deploy"
    assert output =~ "mix sysd.rollback"
    assert output =~ "mix sysd.status"
    assert output =~ "mix sysd.start"
    assert output =~ "mix sysd.stop"
    assert output =~ "mix sysd.restart"
    assert output =~ "mix sysd.tail"
    assert output =~ "mix sysd.cleanup"
  end
end
