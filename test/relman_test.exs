defmodule RelmanTest do
  use ExUnit.Case

  test "app_name returns the application name" do
    assert Relman.app_name() == :relman
  end

  test "version returns a version string" do
    assert is_binary(Relman.version())
  end

  test "release_tar_path includes app name and version" do
    path = Relman.release_tar_path()
    assert path =~ "relman"
    assert path =~ ".tar.gz"
  end

  test "path helpers return expected paths" do
    assert Relman.base_path() == "/opt/relman"
    assert Relman.app_path(:myapp) == "/opt/relman/myapp"
    assert Relman.archives_path(:myapp) == "/opt/relman/myapp/archives"
    assert Relman.releases_path(:myapp) == "/opt/relman/myapp/releases"
    assert Relman.current_path(:myapp) == "/opt/relman/myapp/current"
  end
end
