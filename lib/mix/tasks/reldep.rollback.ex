defmodule Mix.Tasks.Reldep.Rollback do
  @shortdoc "Rollback to a previous version"

  @moduledoc """
  Roll back to a previously deployed release version.

      $ mix reldep.rollback VERSION

  For each server in `config/reldep.yaml`, this task will:

    1. Update the `/opt/reldep/<appname>/current` symlink to point to
       `/opt/reldep/<appname>/releases/<VERSION>`
    2. Restart the systemd service

  The target version must already exist on the server. Use
  `mix reldep.versions` to see available versions.
  """
  use Mix.Task

  alias RelDep.{Config, SSH, Remote}

  @impl Mix.Task
  def run(args) do
    case args do
      [version] ->
        config = Config.load()
        app_name = RelDep.app_name()

        Enum.each(config.servers, fn server ->
          Mix.shell().info("Rolling back #{server} to #{version}...")

          {:ok, conn} = SSH.connect(server, config.ssh)
          Remote.rollback(conn, app_name, version)

          Mix.shell().info("  Rolled back successfully")
        end)

      _ ->
        Mix.raise("Usage: mix reldep.rollback VERSION")
    end
  end
end
