defmodule Mix.Tasks.Sysd.Init do
  @shortdoc "Generate config stubs"

  @moduledoc """
  Generate Sysd configuration files for your project.

      $ mix sysd.init

  Creates the following files if they do not already exist:

    * `config/sysd.yaml` — server list and SSH settings
    * `priv/sysd/<appname>.service` — systemd unit file

  The YAML config is pre-filled with a placeholder server and a default
  `deploy` user. Edit it to match your environment before running
  `mix sysd.sshcheck`.

  The systemd service file is rendered from an EEX template and can be
  customized before running `mix sysd.setup`.

  Existing files are never overwritten.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    app_name = Sysd.app_name()
    config_path = Sysd.Config.config_path()
    service_path = "priv/sysd/#{app_name}.service"
    user_name = System.get_env("USER")

    if File.exists?(config_path) do
      Mix.shell().info("Config already exists: #{config_path}")
    else
      yaml = """
      servers:
        - host1
      ssh:
        user: #{user_name}

      # Optional: publish release tarballs to one or more external
      # artifact stores. Omit this block entirely for a local-only
      # build. Publishers are invoked in the order they appear.
      #
      # release:
      #   publish:
      #     - type: github
      #       draft: false
      #       prerelease: false
      #     - type: file
      #       path: /mnt/releases/#{app_name}/
      """

      File.mkdir_p!(Path.dirname(config_path))
      File.write!(config_path, yaml)
      Mix.shell().info("Created #{config_path}")
    end

    if File.exists?(service_path) do
      Mix.shell().info("Service file already exists: #{service_path}")
    else
      template_path =
        :sysd
        |> :code.priv_dir()
        |> Path.join("sysd/templates/app.service.eex")

      content = EEx.eval_file(template_path, app_name: app_name, user: user_name)

      File.mkdir_p!(Path.dirname(service_path))
      File.write!(service_path, content)
      Mix.shell().info("Created #{service_path}")
    end
  end
end
