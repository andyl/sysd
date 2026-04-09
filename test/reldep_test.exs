defmodule RelDepTest do
  use ExUnit.Case

  test "app_name returns the application name" do
    assert RelDep.app_name() == :reldep
  end

  test "version returns a version string" do
    assert is_binary(RelDep.version())
  end

  test "release_tar_path includes app name and version" do
    path = RelDep.release_tar_path()
    assert path =~ "reldep"
    assert path =~ ".tar.gz"
  end

  test "version_tag prepends v" do
    assert RelDep.version_tag() == "v#{RelDep.version()}"
  end

  test "tarball_basename has the expected shape" do
    assert RelDep.tarball_basename() == "reldep-#{RelDep.version()}.tar.gz"
  end

  test "build_host returns a non-empty string" do
    assert is_binary(RelDep.build_host())
    assert RelDep.build_host() != ""
  end

  test "git_tag_exists? returns a boolean" do
    assert is_boolean(RelDep.git_tag_exists?("definitely-not-a-real-tag-xyz"))
  end

  test "path helpers return expected paths" do
    assert RelDep.base_path() == "/opt/reldep"
    assert RelDep.app_path(:myapp) == "/opt/reldep/myapp"
    assert RelDep.archives_path(:myapp) == "/opt/reldep/myapp/archives"
    assert RelDep.releases_path(:myapp) == "/opt/reldep/myapp/releases"
    assert RelDep.current_path(:myapp) == "/opt/reldep/myapp/current"
  end
end
