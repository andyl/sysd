defmodule Mix.Tasks.Sysd.Init do
  @shortdoc "Generate config stubs"

  @moduledoc """
  Generate Sysd configuration files for your project.

      $ mix sysd.init

  Creates `config/sysd.yaml` if it does not already exist, pre-filled
  with a placeholder server and a default `deploy` user. Edit it to
  match your environment before running `mix sysd.check`.

  Systemd service files are generated automatically during
  `mix sysd.setup` and do not need to be created manually.

  Existing files are never overwritten.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    config_path = Sysd.Config.config_path()
    user_name = System.get_env("USER")

    if File.exists?(config_path) do
      Mix.shell().info("Config already exists: #{config_path}")
    else
      yaml = """
      servers:
        - host1
      ssh:
        user: #{user_name}
      """

      File.mkdir_p!(Path.dirname(config_path))
      File.write!(config_path, yaml)
      Mix.shell().info("Created #{config_path}")
    end
  end
end
