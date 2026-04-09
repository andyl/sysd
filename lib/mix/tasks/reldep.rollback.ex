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

  @impl Mix.Task
  def run(args) do
    case args do
      [version] ->
        config = RelDep.Config.load()
        app_name = RelDep.app_name()

        Enum.each(config.servers, fn server ->
          Mix.shell().info("Rolling back #{server} to #{version}...")

          case RelDep.Deploy.rollback(server, version, app: app_name, config: config) do
            {:ok, :rolled_back} ->
              Mix.shell().info("  Rolled back successfully")

            {:error, reason} ->
              Mix.raise("Rollback failed on #{server}: #{reason}")
          end
        end)

      _ ->
        Mix.raise("Usage: mix reldep.rollback VERSION")
    end
  end
end
