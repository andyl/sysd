defmodule Mix.Tasks.Relman.Rollback do
  @shortdoc "Rollback to a previous version"

  @moduledoc """
  Roll back to a previously deployed release version.

      $ mix relman.rollback VERSION

  For each server in `config/relman.yaml`, this task will:

    1. Update the `/opt/relman/<appname>/current` symlink to point to
       `/opt/relman/<appname>/releases/<VERSION>`
    2. Restart the systemd service

  The target version must already exist on the server. Use
  `mix relman.versions` to see available versions.
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
          Mix.shell().info("Rolling back #{server} to #{version}...")

          {:ok, conn} = SSH.connect(server, config.ssh)
          Remote.rollback(conn, app_name, version)

          Mix.shell().info("  Rolled back successfully")
        end)

      _ ->
        Mix.raise("Usage: mix relman.rollback VERSION")
    end
  end
end
