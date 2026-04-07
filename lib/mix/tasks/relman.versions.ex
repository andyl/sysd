defmodule Mix.Tasks.Relman.Versions do
  @shortdoc "List release versions on servers"

  @moduledoc """
  List deployed release versions on all configured servers.

      $ mix relman.versions

  For each server in `config/relman.yaml`, lists every version found
  under `/opt/relman/<appname>/releases/`. The currently active version (the
  target of the `/opt/relman/<appname>/current` symlink) is marked with
  `(current)`.
  """
  use Mix.Task

  alias Relman.{Config, SSH, Remote}

  @impl Mix.Task
  def run(_args) do
    config = Config.load()
    app_name = Relman.app_name()

    Enum.each(config.servers, fn server ->
      Mix.shell().info("#{server}:")

      {:ok, conn} = SSH.connect(server, config.ssh)
      current = Remote.current_version(conn, app_name)
      versions = Remote.list_versions(conn, app_name)

      if Enum.empty?(versions) do
        Mix.shell().info("  No versions found")
      else
        Enum.each(versions, fn ver ->
          marker = if ver == current, do: " (current)", else: ""
          Mix.shell().info("  #{ver}#{marker}")
        end)
      end
    end)
  end
end
