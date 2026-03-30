defmodule Mix.Tasks.Ziprel.Init do
  @shortdoc "Generate config stubs"

  @moduledoc """
  Generate Ziprel configuration files for your project.

      $ mix ziprel.init

  Creates the following files if they do not already exist:

    * `config/ziprel.yaml` — server list and SSH settings
    * `priv/ziprel/<appname>.service` — systemd unit file

  The YAML config is pre-filled with a placeholder server and a default
  `deploy` user. Edit it to match your environment before running
  `mix ziprel.sshcheck`.

  The systemd service file is rendered from an EEX template and can be
  customized before running `mix ziprel.setup`.

  Existing files are never overwritten.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    app_name = Ziprel.app_name()
    config_path = Ziprel.Config.config_path()
    service_path = "priv/ziprel/#{app_name}.service"
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

    if File.exists?(service_path) do
      Mix.shell().info("Service file already exists: #{service_path}")
    else
      template_path =
        :ziprel
        |> :code.priv_dir()
        |> Path.join("ziprel/templates/app.service.eex")

      content = EEx.eval_file(template_path, app_name: app_name, user: user_name)

      File.mkdir_p!(Path.dirname(service_path))
      File.write!(service_path, content)
      Mix.shell().info("Created #{service_path}")
    end
  end
end
