defmodule Mix.Tasks.Relman.Init do
  @shortdoc "Generate config stubs"

  @moduledoc """
  Generate Relman configuration files for your project.

      $ mix relman.init

  Creates the following files if they do not already exist:

    * `config/relman.yaml` — server list and SSH settings
    * `priv/relman/<appname>.service` — systemd unit file

  The YAML config is pre-filled with a placeholder server and a default
  `deploy` user. Edit it to match your environment before running
  `mix relman.sshcheck`.

  The systemd service file is rendered from an EEX template and can be
  customized before running `mix relman.setup`.

  Existing files are never overwritten.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    app_name = Relman.app_name()
    config_path = Relman.Config.config_path()
    service_path = "priv/relman/#{app_name}.service"
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
        :relman
        |> :code.priv_dir()
        |> Path.join("relman/templates/app.service.eex")

      content = EEx.eval_file(template_path, app_name: app_name, user: user_name)

      File.mkdir_p!(Path.dirname(service_path))
      File.write!(service_path, content)
      Mix.shell().info("Created #{service_path}")
    end
  end
end
