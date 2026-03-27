defmodule ZiprelTest do
  use ExUnit.Case

  test "app_name returns the application name" do
    assert Ziprel.app_name() == :ziprel
  end

  test "version returns a version string" do
    assert is_binary(Ziprel.version())
  end

  test "release_tar_path includes app name and version" do
    path = Ziprel.release_tar_path()
    assert path =~ "ziprel"
    assert path =~ ".tar.gz"
  end

  test "path helpers return expected paths" do
    assert Ziprel.base_path() == "/opt/ziprel"
    assert Ziprel.archives_path() == "/opt/ziprel/archives"
    assert Ziprel.releases_path() == "/opt/ziprel/releases"
    assert Ziprel.current_path() == "/opt/ziprel/current"
  end
end
