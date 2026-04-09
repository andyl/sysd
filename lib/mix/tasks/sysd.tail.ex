defmodule Mix.Tasks.Sysd.Tail do
  @shortdoc "Tail journal logs from a server"

  @moduledoc """
  Tail systemd journal logs from a specific server.

      $ mix sysd.tail SERVER

  A server name is required because tailing is time-bounded (default
  10 seconds) and running sequentially across multiple servers would
  not produce useful output.

  The command runs `journalctl -f` for the configured duration, then
  returns. Output is printed as it arrives.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    config = Sysd.Config.load()
    app_name = Sysd.app_name()

    server =
      case {args, config.servers} do
        {[server], _} ->
          unless server in config.servers do
            Mix.raise("Unknown server: #{server} (not in config/sysd.yaml)")
          end

          server

        {[], [single]} ->
          single

        _ ->
          Mix.raise("Usage: mix sysd.tail SERVER")
      end

    Mix.shell().info("Tailing #{server} (10s)...")

    case Sysd.Deploy.tail(server, app: app_name, config: config) do
      {:ok, output} -> Mix.shell().info(output)
      {:error, reason} -> Mix.shell().error("Failed: #{inspect(reason)}")
    end
  end
end
