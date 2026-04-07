defmodule Mix.Tasks.Relman.Remove do
  @shortdoc "Remove old releases"

  @moduledoc """
  Remove an old release version from all configured servers.

      $ mix relman.remove VERSION

  For each server in `config/relman.yaml`, this task will delete:

    * `/opt/relman/<appname>/releases/<VERSION>/`
    * `/opt/relman/<appname>/archives/<VERSION>.tar.gz`

  The currently active version cannot be removed. Use
  `mix relman.versions` to check which version is current, and
  `mix relman.rollback` to switch away from it first if needed.
  """
  use Mix.Task

  alias Relman.{Config, SSH, Remote}

  @impl Mix.Task
  def run(args) do
    case args do
      [version] ->
        config = Config.load()

        app_name = Relman.app_name()

        Enum.each(config.servers, fn server ->
          Mix.shell().info("Removing #{version} from #{server}...")

          {:ok, conn} = SSH.connect(server, config.ssh)
          Remote.remove_version(conn, app_name, version)

          Mix.shell().info("  Removed successfully")
        end)

      _ ->
        Mix.raise("Usage: mix relman.remove VERSION")
    end
  end
end
