defmodule Mix.Tasks.Sysd.Stop do
  @shortdoc "Stop the systemd service"

  @moduledoc """
  Stop the systemd service on configured servers.

      $ mix sysd.stop [SERVER]

  Without arguments, stops the service on all servers in
  `config/sysd.yaml`. With a server name, stops only on that server.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")
    config = Sysd.Config.load()
    app_name = Sysd.app_name()
    {opts, servers} = parse_args(args, config)

    Enum.each(servers, fn server ->
      Mix.shell().info("Stopping #{server}...")

      case Sysd.Deploy.stop(server, [app: app_name, config: config] ++ opts) do
        {:ok, :stopped} ->
          Mix.shell().info("  Stopped")

        {:error, reason} ->
          Mix.shell().error("  Failed: #{inspect(reason)}")
      end
    end)
  end

  defp parse_args(args, config) do
    {parsed, rest, _} =
      OptionParser.parse(args, strict: [instance: :string], aliases: [i: :instance])

    opts = if parsed[:instance], do: [instance: parsed[:instance]], else: []
    servers = target_servers(rest, config)
    {opts, servers}
  end

  defp target_servers([], config), do: config.servers

  defp target_servers([server], config) do
    if server in config.servers do
      [server]
    else
      Mix.raise("Unknown server: #{server} (not in config/sysd.yaml)")
    end
  end

  defp target_servers(_, _config),
    do: Mix.raise("Usage: mix sysd.stop [SERVER] [--instance NAME]")
end
