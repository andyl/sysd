defmodule Sysd.Publisher.GithubTest do
  use ExUnit.Case, async: true

  alias Sysd.Publisher.Github.Util

  describe "origin_repo/1" do
    test "parses an https URL without .git" do
      assert {:ok, "andyl/release_deployer"} =
               Util.origin_repo("https://github.com/andyl/release_deployer")
    end

    test "parses an https URL with .git" do
      assert {:ok, "andyl/release_deployer"} =
               Util.origin_repo("https://github.com/andyl/release_deployer.git")
    end

    test "parses a git@ ssh URL without .git" do
      assert {:ok, "andyl/release_deployer"} =
               Util.origin_repo("git@github.com:andyl/release_deployer")
    end

    test "parses a git@ ssh URL with .git" do
      assert {:ok, "andyl/release_deployer"} =
               Util.origin_repo("git@github.com:andyl/release_deployer.git")
    end

    test "strips surrounding whitespace" do
      assert {:ok, "o/r"} = Util.origin_repo("  https://github.com/o/r.git\n")
    end

    test "rejects non-github URLs" do
      assert {:error, _} = Util.origin_repo("https://gitlab.com/o/r.git")
    end

    test "errors on blank input" do
      assert {:error, _} = Util.origin_repo("")
    end
  end

  describe "release_create_args/5" do
    test "base argv has no draft or prerelease flags" do
      args = Util.release_create_args(%{}, "v1.0.0", "tar.gz", :myapp, "1.0.0")

      assert args == [
               "release",
               "create",
               "v1.0.0",
               "tar.gz",
               "--title",
               "myapp v1.0.0",
               "--notes",
               ""
             ]
    end

    test "appends --draft when draft: true" do
      args = Util.release_create_args(%{draft: true}, "v1", "t", :a, "1")
      assert "--draft" in args
      refute "--prerelease" in args
    end

    test "appends --prerelease when prerelease: true" do
      args = Util.release_create_args(%{prerelease: true}, "v1", "t", :a, "1")
      assert "--prerelease" in args
      refute "--draft" in args
    end

    test "appends both when both flags are set" do
      args = Util.release_create_args(%{draft: true, prerelease: true}, "v1", "t", :a, "1")
      assert "--draft" in args
      assert "--prerelease" in args
    end
  end
end
