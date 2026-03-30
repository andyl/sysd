defmodule Mix.Tasks.Ziprel.Versions do
  @shortdoc "List release versions on servers"

  @moduledoc """
  List deployed release versions on all configured servers.

      $ mix ziprel.versions

  For each server in `config/ziprel.yaml`, lists every version found
  under `/opt/ziprel/<appname>/releases/`. The currently active version (the
  target of the `/opt/ziprel/<appname>/current` symlink) is marked with
  `(current)`.
  """
  use Mix.Task

  alias Ziprel.{Config, SSH, Remote}

  @impl Mix.Task
  def run(_args) do
    config = Config.load()
    app_name = Ziprel.app_name()

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
