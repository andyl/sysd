defmodule Mix.Tasks.Sysd.Status do
  @shortdoc "Show systemd service status"

  @moduledoc """
  Show the systemd service status on configured servers.

      $ mix sysd.status [SERVER]

  Without arguments, checks all servers in `config/sysd.yaml`.
  With a server name, checks only that server.

  Reports the output of `systemctl is-active` for each server
  (e.g. `active`, `inactive`, `failed`).
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    config = Sysd.Config.load()
    app_name = Sysd.app_name()
    servers = target_servers(args, config)

    Enum.each(servers, fn server ->
      case Sysd.Deploy.status(server, app: app_name, config: config) do
        {:ok, status} ->
          Mix.shell().info("#{server}: #{status}")

        {:error, reason} ->
          Mix.shell().error("#{server}: #{inspect(reason)}")
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

  defp target_servers(_, _config), do: Mix.raise("Usage: mix sysd.status [SERVER]")
end
