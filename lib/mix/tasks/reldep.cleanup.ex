defmodule Mix.Tasks.Reldep.Cleanup do
  @shortdoc "Remove everything from server"

  @moduledoc """
  Completely remove RelDep from a server.

      $ mix reldep.cleanup SERVER

  This task will:

    1. Stop and disable the systemd service
    2. Remove the service file from `/etc/systemd/system/`
    3. Delete the `/opt/reldep/<appname>/` directory
    4. Remove the server entry from `config/reldep.yaml`

  This is a destructive operation. The server must be listed in
  `config/reldep.yaml`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case args do
      [server] ->
        config = RelDep.Config.load()
        app_name = RelDep.app_name()

        unless server in config.servers do
          Mix.raise("Server #{server} not found in config")
        end

        Mix.shell().info("Cleaning up #{server}...")

        case RelDep.Deploy.cleanup(server, app: app_name, config: config) do
          {:ok, :cleaned_up} ->
            RelDep.Config.remove_server(config, server)
            Mix.shell().info("  Removed all RelDep files and config for #{server}")

          {:error, reason} ->
            Mix.raise("Cleanup failed on #{server}: #{reason}")
        end

      _ ->
        Mix.raise("Usage: mix reldep.cleanup SERVER")
    end
  end
end
