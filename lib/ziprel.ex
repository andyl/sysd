defmodule Ziprel do
  @moduledoc """
  Helpers and path constants for Ziprel deployments.

  Provides the remote directory layout used on target servers and
  convenience functions for deriving application metadata from the
  current Mix project.

  ## Remote Directory Layout

      /opt/ziprel/<appname>/
        archives/<version>.tar.gz
        releases/<version>/
        current -> releases/<version>

  Each application gets its own subdirectory under `/opt/ziprel/`,
  allowing multiple apps to be deployed on the same server.
  """

  @base_path "/opt/ziprel"

  @doc "Root path for all Ziprel files on the remote server."
  def base_path, do: @base_path

  @doc "Per-application root path on the remote server."
  def app_path(app_name), do: Path.join(@base_path, to_string(app_name))

  @doc "Remote directory where release tarballs are stored for an app."
  def archives_path(app_name), do: Path.join(app_path(app_name), "archives")

  @doc "Remote directory containing extracted release versions for an app."
  def releases_path(app_name), do: Path.join(app_path(app_name), "releases")

  @doc "Symlink on the remote server pointing to the active release for an app."
  def current_path(app_name), do: Path.join(app_path(app_name), "current")

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
    Path.join([Mix.Project.build_path(), "#{app}-#{ver}.tar.gz"])
  end
end
