defmodule Mix.Tasks.Ziprel.Remove do
  @shortdoc "Remove old releases"

  @moduledoc """
  Remove an old release version from all configured servers.

      $ mix ziprel.remove VERSION

  For each server in `config/ziprel.yaml`, this task will delete:

    * `/opt/ziprel/releases/<VERSION>/`
    * `/opt/ziprel/archives/<VERSION>.tar.gz`

  The currently active version cannot be removed. Use
  `mix ziprel.versions` to check which version is current, and
  `mix ziprel.rollback` to switch away from it first if needed.
  """
  use Mix.Task

  alias Ziprel.{Config, SSH, Remote}

  @impl Mix.Task
  def run(args) do
    case args do
      [version] ->
        config = Config.load()

        Enum.each(config.servers, fn server ->
          Mix.shell().info("Removing #{version} from #{server}...")

          {:ok, conn} = SSH.connect(server, config.ssh)
          Remote.remove_version(conn, version)

          Mix.shell().info("  Removed successfully")
        end)

      _ ->
        Mix.raise("Usage: mix ziprel.remove VERSION")
    end
  end
end
