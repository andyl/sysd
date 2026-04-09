defmodule Mix.Tasks.Reldep.Setup do
  @shortdoc "Setup servers for deployment"

  @moduledoc """
  Perform first-time server setup on all configured servers.

      $ mix reldep.setup

  For each server listed in `config/reldep.yaml`, this task will:

    1. Create the remote directory structure at `/opt/reldep/<appname>/`
    2. Install the systemd service file (rendered from embedded template)
    3. Enable the systemd service

  Run `mix reldep.init` first to generate the config, then
  `mix reldep.sshcheck` to validate connectivity.

  After setup completes, run `mix reldep.deploy` to perform your first
  deployment.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    config = RelDep.Config.load()
    app_name = RelDep.app_name()

    Enum.each(config.servers, fn server ->
      Mix.shell().info("Setting up #{server}...")

      case RelDep.Deploy.setup(server,
             app: app_name,
             user: config.ssh[:user] || "deploy",
             config: config
           ) do
        {:ok, :setup_complete} ->
          Mix.shell().info("  Created directory structure")
          Mix.shell().info("  Installed systemd service")

        {:error, reason} ->
          Mix.raise("Setup failed on #{server}: #{reason}")
      end
    end)

    Mix.shell().info("\nSetup complete. Run `mix reldep.deploy` to deploy your app.")
  end
end
