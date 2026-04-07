defmodule Mix.Tasks.Relman.Sshcheck do
  @shortdoc "Check SSH connection and permissions"

  @moduledoc """
  Verify SSH connectivity and permissions on all configured servers.

      $ mix relman.sshcheck

  For each server listed in `config/relman.yaml`, this task will:

    1. Open an SSH connection using the configured user and SSH agent
    2. Run `whoami` to confirm the connection works
    3. Run `sudo -n true` to verify passwordless sudo access
    4. Test that `/opt/relman/<appname>` can be created

  A pass/fail summary is printed for each server. Fix any failures
  before running `mix relman.setup`.
  """
  use Mix.Task

  alias Relman.SSH

  @impl Mix.Task
  def run(_args) do
    config = Relman.Config.load()

    Enum.each(config.servers, fn server ->
      Mix.shell().info("Checking #{server}...")

      case SSH.connect(server, config.ssh) do
        {:ok, conn} ->
          check_connection(conn, server)
          check_sudo(conn, server)
          check_directory(conn, server)

        {:error, reason} ->
          Mix.shell().error("  SSH connection failed: #{inspect(reason)}")
      end
    end)
  end

  defp check_connection(conn, server) do
    case SSH.run(conn, "whoami") do
      {:ok, user, 0} ->
        Mix.shell().info("  Connected as #{String.trim(user)}")

      _ ->
        Mix.shell().error("  #{server}: connection test failed")
    end
  end

  defp check_sudo(conn, server) do
    case SSH.run(conn, "sudo -n true") do
      {:ok, _, 0} ->
        Mix.shell().info("  Sudo access: OK")

      _ ->
        Mix.shell().error("  #{server}: passwordless sudo not available")
    end
  end

  defp check_directory(conn, server) do
    app_path = Relman.app_path(Relman.app_name())

    case SSH.run(conn, "sudo mkdir -p #{app_path} && sudo rmdir #{app_path} 2>/dev/null; echo ok") do
      {:ok, _, 0} ->
        Mix.shell().info("  Directory access: OK")

      _ ->
        Mix.shell().error("  #{server}: cannot create #{app_path}")
    end
  end
end
