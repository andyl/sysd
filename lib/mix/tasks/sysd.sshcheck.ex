defmodule Mix.Tasks.Sysd.Sshcheck do
  @shortdoc "Check SSH connection and permissions"

  @moduledoc """
  Verify SSH connectivity and permissions on all configured servers.

      $ mix sysd.sshcheck

  For each server listed in `config/sysd.yaml`, this task will:

    1. Open an SSH connection using the configured user and SSH agent
    2. Run `whoami` to confirm the connection works
    3. Run `sudo -n true` to verify passwordless sudo access
    4. Test that `/opt/sysd/<appname>` can be created

  A pass/fail summary is printed for each server. Fix any failures
  before running `mix sysd.setup`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    config = Sysd.Config.load()
    app_name = Sysd.app_name()

    Enum.each(config.servers, fn server ->
      Mix.shell().info("Checking #{server}...")

      case Sysd.Deploy.check(server, app: app_name, config: config) do
        {:ok, checks} ->
          case checks.connection do
            {:ok, user} -> Mix.shell().info("  Connected as #{user}")
            {:error, msg} -> Mix.shell().error("  #{server}: #{msg}")
          end

          case checks.sudo do
            :ok -> Mix.shell().info("  Sudo access: OK")
            {:error, msg} -> Mix.shell().error("  #{server}: #{msg}")
          end

          case checks.directory do
            :ok -> Mix.shell().info("  Directory access: OK")
            {:error, msg} -> Mix.shell().error("  #{server}: #{msg}")
          end

        {:error, reason} ->
          Mix.shell().error("  SSH connection failed: #{inspect(reason)}")
      end
    end)
  end
end
