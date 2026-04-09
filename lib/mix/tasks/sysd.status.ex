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
    {opts, servers} = parse_args(args, config)

    Enum.each(servers, fn server ->
      case Sysd.Deploy.status(server, [app: app_name, config: config] ++ opts) do
        {:ok, status} when is_binary(status) ->
          Mix.shell().info("#{server}: #{status}")

        {:ok, status} when is_map(status) ->
          Mix.shell().info("#{server}:")
          Enum.each(status, fn {svc, s} -> Mix.shell().info("  #{svc}: #{s}") end)

        {:error, reason} ->
          Mix.shell().error("#{server}: #{inspect(reason)}")
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
    do: Mix.raise("Usage: mix sysd.status [SERVER] [--instance NAME]")
end
