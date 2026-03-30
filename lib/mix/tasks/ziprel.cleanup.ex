defmodule Mix.Tasks.Ziprel.Cleanup do
  @shortdoc "Remove everything from server"

  @moduledoc """
  Completely remove Ziprel from a server.

      $ mix ziprel.cleanup SERVER

  This task will:

    1. Stop and disable the systemd service
    2. Remove the service file from `/etc/systemd/system/`
    3. Delete the `/opt/ziprel/<appname>/` directory
    4. Remove the server entry from `config/ziprel.yaml`

  This is a destructive operation. The server must be listed in
  `config/ziprel.yaml`.
  """
  use Mix.Task

  alias Ziprel.{Config, SSH, Remote}

  @impl Mix.Task
  def run(args) do
    case args do
      [server] ->
        config = Config.load()
        app_name = Ziprel.app_name()

        unless server in config.servers do
          Mix.raise("Server #{server} not found in config")
        end

        Mix.shell().info("Cleaning up #{server}...")

        {:ok, conn} = SSH.connect(server, config.ssh)
        Remote.cleanup(conn, app_name)

        Config.remove_server(config, server)

        Mix.shell().info("  Removed all Ziprel files and config for #{server}")

      _ ->
        Mix.raise("Usage: mix ziprel.cleanup SERVER")
    end
  end
end
