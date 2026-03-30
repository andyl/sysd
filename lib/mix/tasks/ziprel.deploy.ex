defmodule Mix.Tasks.Ziprel.Deploy do
  @shortdoc "Deploy app to servers"

  @moduledoc """
  Build a release and deploy it to all configured servers.

      $ mix ziprel.deploy

  This task will:

    1. Build a production release with `MIX_ENV=prod mix release`
    2. Locate the release tarball in `_build/prod/rel/`
    3. For each server in `config/ziprel.yaml`:
       - Upload the tarball to `/opt/ziprel/<appname>/archives/<version>.tar.gz`
       - Extract it to `/opt/ziprel/<appname>/releases/<version>/`
       - Update the `/opt/ziprel/<appname>/current` symlink to the new version
       - Start or restart the systemd service

  The service will be briefly offline during the deploy.

  Run `mix ziprel.setup` before your first deployment to prepare the
  remote servers.
  """
  use Mix.Task

  alias Ziprel.{Config, SSH, Remote}

  @impl Mix.Task
  def run(_args) do
    config = Config.load()
    app_name = Ziprel.app_name()
    version = Ziprel.version()

    Mix.shell().info("Building release #{app_name} #{version}...")
    Mix.shell().info("running `mix assets.deploy`...")
    Mix.Task.run("assets.deploy", [])
    Mix.shell().info("running `mix release`...")
    Mix.Task.run("release", [])

    tar_path = Ziprel.release_tar_path()

    unless File.exists?(tar_path) do
      Mix.raise("""
      Release tarball not found: #{tar_path}
      Make sure your release config includes `include_erts: true` or that the tarball was generated.
      """)
    end

    Enum.each(config.servers, fn server ->
      Mix.shell().info("Deploying #{version} to #{server}...")

      {:ok, conn} = SSH.connect(server, config.ssh)
      Remote.deploy(conn, app_name, tar_path, version)

      Mix.shell().info("  Deployed successfully")
    end)
  end
end
