defmodule Mix.Tasks.Relman.Cleanup do
  @shortdoc "Remove everything from server"

  @moduledoc """
  Completely remove Relman from a server.

      $ mix relman.cleanup SERVER

  This task will:

    1. Stop and disable the systemd service
    2. Remove the service file from `/etc/systemd/system/`
    3. Delete the `/opt/relman/<appname>/` directory
    4. Remove the server entry from `config/relman.yaml`

  This is a destructive operation. The server must be listed in
  `config/relman.yaml`.
  """
  use Mix.Task

  alias Relman.{Config, SSH, Remote}

  @impl Mix.Task
  def run(args) do
    case args do
      [server] ->
        config = Config.load()
        app_name = Relman.app_name()

        unless server in config.servers do
          Mix.raise("Server #{server} not found in config")
        end

        Mix.shell().info("Cleaning up #{server}...")

        {:ok, conn} = SSH.connect(server, config.ssh)
        Remote.cleanup(conn, app_name)

        Config.remove_server(config, server)

        Mix.shell().info("  Removed all Relman files and config for #{server}")

      _ ->
        Mix.raise("Usage: mix relman.cleanup SERVER")
    end
  end
end
