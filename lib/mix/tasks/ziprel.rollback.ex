defmodule Mix.Tasks.Ziprel.Rollback do
  @shortdoc "Rollback to a previous version"

  @moduledoc """
  Roll back to a previously deployed release version.

      $ mix ziprel.rollback VERSION

  For each server in `config/ziprel.yaml`, this task will:

    1. Update the `/opt/ziprel/current` symlink to point to
       `/opt/ziprel/releases/<VERSION>`
    2. Restart the systemd service

  The target version must already exist on the server. Use
  `mix ziprel.versions` to see available versions.
  """
  use Mix.Task

  alias Ziprel.{Config, SSH, Remote}

  @impl Mix.Task
  def run(args) do
    case args do
      [version] ->
        config = Config.load()
        app_name = Ziprel.app_name()

        Enum.each(config.servers, fn server ->
          Mix.shell().info("Rolling back #{server} to #{version}...")

          {:ok, conn} = SSH.connect(server, config.ssh)
          Remote.rollback(conn, app_name, version)

          Mix.shell().info("  Rolled back successfully")
        end)

      _ ->
        Mix.raise("Usage: mix ziprel.rollback VERSION")
    end
  end
end
