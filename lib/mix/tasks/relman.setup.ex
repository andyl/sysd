defmodule Mix.Tasks.Relman.Setup do
  @shortdoc "Setup servers for deployment"

  @moduledoc """
  Perform first-time server setup on all configured servers.

      $ mix relman.setup

  For each server listed in `config/relman.yaml`, this task will:

    1. Create the remote directory structure at `/opt/relman/<appname>/`
    2. Install the systemd service file from `priv/relman/<appname>.service`
    3. Enable the systemd service

  Run `mix relman.init` first to generate the config and service files,
  then `mix relman.sshcheck` to validate connectivity.

  After setup completes, run `mix relman.deploy` to perform your first
  deployment.
  """
  use Mix.Task

  alias Relman.{Config, SSH, Remote}

  @impl Mix.Task
  def run(_args) do
    config = Config.load()
    app_name = Relman.app_name()

    service_path = "priv/relman/#{app_name}.service"

    unless File.exists?(service_path) do
      Mix.raise("Service file not found: #{service_path}\nRun `mix relman.init` first.")
    end

    service_content = File.read!(service_path)

    Enum.each(config.servers, fn server ->
      Mix.shell().info("Setting up #{server}...")

      {:ok, conn} = SSH.connect(server, config.ssh)

      Remote.setup_dirs(conn, app_name)
      Mix.shell().info("  Created directory structure")

      Remote.install_service(conn, app_name, service_content)
      Mix.shell().info("  Installed systemd service")
    end)

    Mix.shell().info("\nSetup complete. Run `mix relman.deploy` to deploy your app.")
  end
end
