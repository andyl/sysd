defmodule ZiprelTest do
  use ExUnit.Case
  doctest Ziprel

  test "greets the world" do
    assert Ziprel.hello() == :world
  end
end
