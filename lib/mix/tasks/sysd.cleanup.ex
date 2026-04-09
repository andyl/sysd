defmodule Mix.Tasks.Sysd.Cleanup do
  @shortdoc "Remove everything from server"

  @moduledoc """
  Completely remove Sysd from a server.

      $ mix sysd.cleanup SERVER

  This task will:

    1. Stop and disable the systemd service
    2. Remove the service file from `/etc/systemd/system/`
    3. Delete the `/opt/sysd/<appname>/` directory
    4. Remove the server entry from `config/sysd.yaml`

  This is a destructive operation. The server must be listed in
  `config/sysd.yaml`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    {parsed, rest, _} =
      OptionParser.parse(args, strict: [instance: :string], aliases: [i: :instance])

    instance_opts = if parsed[:instance], do: [instance: parsed[:instance]], else: []

    case rest do
      [server] ->
        config = Sysd.Config.load()
        app_name = Sysd.app_name()

        unless server in config.servers do
          Mix.raise("Server #{server} not found in config")
        end

        Mix.shell().info("Cleaning up #{server}...")

        case Sysd.Deploy.cleanup(server, [app: app_name, config: config] ++ instance_opts) do
          {:ok, :cleaned_up} ->
            unless parsed[:instance] do
              Sysd.Config.remove_server(config, server)
            end

            Mix.shell().info("  Removed all Sysd files and config for #{server}")

          {:error, reason} ->
            Mix.raise("Cleanup failed on #{server}: #{reason}")
        end

      _ ->
        Mix.raise("Usage: mix sysd.cleanup SERVER [--instance NAME]")
    end
  end
end
