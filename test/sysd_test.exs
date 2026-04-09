defmodule SysdTest do
  use ExUnit.Case

  test "app_name returns the application name" do
    assert Sysd.app_name() == :release_deployer
  end

  test "version returns a version string" do
    assert is_binary(Sysd.version())
  end

  test "release_tar_path includes app name and version" do
    path = Sysd.release_tar_path()
    assert path =~ "release_deployer"
    assert path =~ ".tar.gz"
  end

  test "version_tag prepends v" do
    assert Sysd.version_tag() == "v#{Sysd.version()}"
  end

  test "tarball_basename has the expected shape" do
    assert Sysd.tarball_basename() == "release_deployer-#{Sysd.version()}.tar.gz"
  end

  test "build_host returns a non-empty string" do
    assert is_binary(Sysd.build_host())
    assert Sysd.build_host() != ""
  end

  test "git_tag_exists? returns a boolean" do
    assert is_boolean(Sysd.git_tag_exists?("definitely-not-a-real-tag-xyz"))
  end

  test "path helpers return expected paths" do
    assert Sysd.base_path() == "/opt/sysd"
    assert Sysd.app_path(:myapp) == "/opt/sysd/myapp"
    assert Sysd.archives_path(:myapp) == "/opt/sysd/myapp/archives"
    assert Sysd.releases_path(:myapp) == "/opt/sysd/myapp/releases"
    assert Sysd.current_path(:myapp) == "/opt/sysd/myapp/current"
  end
end
