defmodule Mix.Tasks.Sysd.Deploy do
  @shortdoc "Deploy an existing release tarball to servers"

  @moduledoc """
  Push an existing release tarball to each configured server.

      $ MIX_ENV=prod mix sysd.deploy

  ## Behavior

    1. If no local tarball exists for `@version`, build one by running
       `mix assets.deploy` followed by `mix release`.
    2. For each server in `config/sysd.yaml`:
       - Upload the tarball to `/opt/sysd/<appname>/archives/<version>.tar.gz`
       - Extract it to `/opt/sysd/<appname>/releases/<version>/`
       - Update the `/opt/sysd/<appname>/current` symlink
       - Start or restart the systemd service
       - Write `/opt/sysd/<appname>/releases/<version>/RELEASE_INFO`
         recording the git sha, build host, and timestamp.

  The service will be briefly offline during the deploy.

  Run `mix sysd.setup` before your first deployment to prepare the
  remote servers.
  """
  use Mix.Task

  alias Sysd.{Config, SSH, Remote}

  @impl Mix.Task
  def run(_args) do
    config = Config.load()
    app_name = Sysd.app_name()
    version = Sysd.version()
    tar_path = Sysd.release_tar_path()

    unless File.exists?(tar_path) do
      Mix.shell().info("No local tarball for #{version}; building release...")
      Mix.Task.run("assets.deploy", [])
      Mix.Task.run("release", [])
    end

    unless File.exists?(tar_path) do
      Mix.raise("Release tarball not found: #{tar_path}")
    end

    release_info = %{
      app: app_name,
      version: version,
      git_sha: Sysd.git_sha(),
      build_host: Sysd.build_host(),
      build_timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Enum.each(config.servers, fn server ->
      Mix.shell().info("Deploying #{version} to #{server}...")

      {:ok, conn} = SSH.connect(server, config.ssh)
      Remote.deploy(conn, app_name, tar_path, version)
      Remote.write_release_info(conn, app_name, version, release_info)

      Mix.shell().info("  Deployed successfully")
    end)
  end
end
