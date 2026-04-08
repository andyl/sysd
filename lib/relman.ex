defmodule Relman do
  @moduledoc """
  Helpers and path constants for Relman deployments.

  Provides the remote directory layout used on target servers and
  convenience functions for deriving application metadata from the
  current Mix project.

  ## Remote Directory Layout

      /opt/relman/<appname>/
        archives/<version>.tar.gz
        releases/<version>/
        current -> releases/<version>

  Each application gets its own subdirectory under `/opt/relman/`,
  allowing multiple apps to be deployed on the same server.
  """

  @base_path "/opt/relman"

  @doc "Root path for all Relman files on the remote server."
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

  @doc "Returns the git tag name (`v<version>`) for the current project version."
  def version_tag, do: "v#{version()}"

  @doc "Returns the tarball basename `<app>-<version>.tar.gz` for the current project."
  def tarball_basename do
    "#{app_name()}-#{version()}.tar.gz"
  end

  @doc "Returns the local path to the release tarball produced by `mix release`."
  def release_tar_path do
    app = app_name()
    ver = version()
    Path.join([Mix.Project.build_path(), "#{app}-#{ver}.tar.gz"])
  end

  @doc """
  Returns the current git sha (`HEAD`), or `nil` if git is unavailable
  or the command fails.
  """
  def git_sha do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> nil
    end
  rescue
    ErlangError -> nil
  end

  @doc """
  Return `true` if the given git tag exists locally.

  Raises a `Mix.Error` with a helpful message if `git` is not on
  `$PATH`.
  """
  def git_tag_exists?(tag) when is_binary(tag) do
    case System.cmd("git", ["rev-parse", "-q", "--verify", "refs/tags/#{tag}"],
           stderr_to_stdout: true
         ) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    ErlangError -> Mix.raise("`git` executable not found on $PATH")
  end

  @doc "Return the local build host name as a string."
  def build_host do
    case :inet.gethostname() do
      {:ok, hostname} -> to_string(hostname)
      _ -> "unknown"
    end
  end
end
