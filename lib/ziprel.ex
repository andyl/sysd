defmodule Ziprel do
  @moduledoc """
  Helpers and path constants for Ziprel deployments.

  Provides the remote directory layout used on target servers and
  convenience functions for deriving application metadata from the
  current Mix project.

  ## Remote Directory Layout

      /opt/ziprel/
        archives/<version>.tar.gz
        releases/<version>/
        current -> releases/<version>
  """

  @base_path "/opt/ziprel"

  @doc "Root path for all Ziprel files on the remote server."
  def base_path, do: @base_path

  @doc "Remote directory where release tarballs are stored."
  def archives_path, do: Path.join(@base_path, "archives")

  @doc "Remote directory containing extracted release versions."
  def releases_path, do: Path.join(@base_path, "releases")

  @doc "Symlink on the remote server pointing to the active release."
  def current_path, do: Path.join(@base_path, "current")

  @doc "Returns the application name atom from the Mix project config."
  def app_name do
    Mix.Project.config()[:app]
  end

  @doc "Returns the version string from the Mix project config."
  def version do
    Mix.Project.config()[:version]
  end

  @doc "Returns the local path to the release tarball produced by `mix release`."
  def release_tar_path do
    app = app_name()
    ver = version()
    Path.join([Mix.Project.build_path(), "rel", to_string(app), "#{app}-#{ver}.tar.gz"])
  end
end
