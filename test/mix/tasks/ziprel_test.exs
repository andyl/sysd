defmodule Mix.Tasks.ZiprelTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "mix ziprel prints help text" do
    output = capture_io(fn -> Mix.Tasks.Ziprel.run([]) end)
    assert output =~ "Ziprel - Deploy Elixir releases"
    assert output =~ "mix ziprel.init"
    assert output =~ "mix ziprel.deploy"
    assert output =~ "mix ziprel.rollback"
    assert output =~ "mix ziprel.cleanup"
  end
end
