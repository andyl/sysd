defmodule Mix.Tasks.Relman.Deploy do
  @shortdoc "Deploy an existing release tarball to servers"

  @moduledoc """
  Push an existing release tarball to each configured server.

      $ MIX_ENV=prod mix relman.deploy
      $ MIX_ENV=prod mix relman.deploy --from-release

  ## Behavior

    1. If no local tarball exists for `@version`, invoke
       `mix relman.release` to build one (the default path). This
       will also run any configured publishers — pass
       `--no-publish` to `relman.release` directly if that is not
       desired.
    2. With `--from-release`, instead fetch the tarball for
       `@version` from the first configured publisher that supports
       fetching. This enables deploying from a machine that did not
       build the artifact.
    3. For each server in `config/relman.yaml`:
       - Upload the tarball to `/opt/relman/<appname>/archives/<version>.tar.gz`
       - Extract it to `/opt/relman/<appname>/releases/<version>/`
       - Update the `/opt/relman/<appname>/current` symlink
       - Start or restart the systemd service
       - Write `/opt/relman/<appname>/releases/<version>/RELEASE_INFO`
         recording the git sha, build host, timestamp, and (if used)
         the publisher URL.

  The service will be briefly offline during the deploy.

  Run `mix relman.setup` before your first deployment to prepare the
  remote servers.

  ## Flags

    * `--from-release` — fetch the tarball from the first fetch-capable
      publisher instead of building locally.
  """
  use Mix.Task

  alias Relman.{Config, SSH, Remote}

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [from_release: :boolean])
    from_release? = Keyword.get(opts, :from_release, false)

    config = Config.load()
    app_name = Relman.app_name()
    version = Relman.version()
    tar_path = Relman.release_tar_path()
    publishers = Config.publishers(config)

    publisher_url =
      cond do
        File.exists?(tar_path) and not from_release? ->
          nil

        from_release? ->
          fetch_from_publisher(publishers, app_name, version, tar_path)

        true ->
          Mix.shell().info("No local tarball for #{version}; invoking `mix relman.release`...")
          Mix.Task.run("relman.release", [])
          nil
      end

    unless File.exists?(tar_path) do
      Mix.raise("Release tarball not found after release step: #{tar_path}")
    end

    release_info = %{
      app: app_name,
      version: version,
      git_sha: Relman.git_sha(),
      build_host: Relman.build_host(),
      build_timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      publisher_url: publisher_url
    }

    Enum.each(config.servers, fn server ->
      Mix.shell().info("Deploying #{version} to #{server}...")

      {:ok, conn} = SSH.connect(server, config.ssh)
      Remote.deploy(conn, app_name, tar_path, version)
      Remote.write_release_info(conn, app_name, version, release_info)

      Mix.shell().info("  Deployed successfully")
    end)
  end

  defp fetch_from_publisher([], _app, _version, _tar_path) do
    Mix.raise("--from-release was passed but no publishers are configured in config/relman.yaml")
  end

  defp fetch_from_publisher(publishers, app_name, version, tar_path) do
    dest_dir = Path.dirname(tar_path)
    Mix.shell().info("Fetching #{app_name} #{version} from configured publishers...")

    case Relman.Publisher.fetch_first(publishers, app_name, version, dest_dir) do
      {:ok, url} ->
        if url, do: Mix.shell().info("  fetched: #{url}")
        url

      {:error, reasons} ->
        Mix.raise("Fetch failed from all publishers:\n  - " <> Enum.join(reasons, "\n  - "))
    end
  end
end
