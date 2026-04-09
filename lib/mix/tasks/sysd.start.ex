defmodule Mix.Tasks.Sysd.Start do
  @shortdoc "Start the systemd service"

  @moduledoc """
  Start the systemd service on configured servers.

      $ mix sysd.start [SERVER]

  Without arguments, starts the service on all servers in
  `config/sysd.yaml`. With a server name, starts only on that server.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    config = Sysd.Config.load()
    app_name = Sysd.app_name()
    servers = target_servers(args, config)

    Enum.each(servers, fn server ->
      Mix.shell().info("Starting #{server}...")

      case Sysd.Deploy.start(server, app: app_name, config: config) do
        {:ok, :started} ->
          Mix.shell().info("  Started")

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

  defp target_servers(_, _config), do: Mix.raise("Usage: mix sysd.start [SERVER]")
end
