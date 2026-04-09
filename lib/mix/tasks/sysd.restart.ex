defmodule Mix.Tasks.Sysd.Restart do
  @shortdoc "Restart the systemd service"

  @moduledoc """
  Restart the systemd service on configured servers.

      $ mix sysd.restart [SERVER]

  Without arguments, restarts the service on all servers in
  `config/sysd.yaml`. With a server name, restarts only on that server.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    config = Sysd.Config.load()
    app_name = Sysd.app_name()
    servers = target_servers(args, config)

    Enum.each(servers, fn server ->
      Mix.shell().info("Restarting #{server}...")

      case Sysd.Deploy.restart(server, app: app_name, config: config) do
        {:ok, :restarted} ->
          Mix.shell().info("  Restarted")

        {:error, reason} ->
          Mix.shell().error("  Failed: #{inspect(reason)}")
      end
    end)
  end

  defp target_servers([], config), do: config.servers

  defp target_servers([server], config) do
    if server in config.servers do
      [server]
    else
      Mix.raise("Unknown server: #{server} (not in config/sysd.yaml)")
    end
  end

  defp target_servers(_, _config), do: Mix.raise("Usage: mix sysd.restart [SERVER]")
end
