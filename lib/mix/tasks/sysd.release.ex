defmodule Mix.Tasks.Sysd.Release do
  @shortdoc "Build a release tarball and optionally publish it"

  @moduledoc """
  Build a production release tarball for the current project and
  optionally publish it to each configured publisher.

      $ MIX_ENV=prod mix sysd.release

  ## Behavior

    1. Verify that the git tag `v<@version>` exists locally. Fail if
       not. Sysd does not create tags — that is `git_ops`' job.
    2. Run preflight checks for every configured publisher **before**
       building, so misconfiguration fails fast.
    3. If a tarball for the current `@version` already exists locally,
       skip the build unless `--force` is passed. Otherwise run
       `mix assets.deploy` followed by `mix release`.
    4. After the build succeeds, invoke each configured publisher in
       order.

  ## Flags

    * `--force` — rebuild the tarball even if one already exists for
      `@version`.
    * `--replace` — delete and recreate an existing published
      artifact (or overwrite the existing file for the file publisher).
    * `--no-publish` — build only; skip all configured publishers.

  Publisher configuration lives under `release.publish` in
  `config/sysd.yaml`. Omitting the key results in a local build with
  no upload.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [force: :boolean, replace: :boolean, no_publish: :boolean]
      )

    force? = Keyword.get(opts, :force, false)
    replace? = Keyword.get(opts, :replace, false)
    publish? = not Keyword.get(opts, :no_publish, false)

    config = Sysd.Config.load()
    app_name = Sysd.app_name()
    version = Sysd.version()
    tag = Sysd.version_tag()
    publishers = Sysd.Config.publishers(config)

    unless Sysd.git_tag_exists?(tag) do
      Mix.raise("""
      git tag #{tag} does not exist locally.
      Run `mix git_ops.release` to bump the version and create the tag.
      """)
    end

    if publish? and publishers != [] do
      Mix.shell().info("Running publisher preflight checks...")

      case Sysd.Publisher.preflight_all(publishers, replace: replace?) do
        :ok ->
          :ok

        {:error, errors} ->
          Mix.raise("Publisher preflight failed:\n  - " <> Enum.join(errors, "\n  - "))
      end
    end

    tar_path = Sysd.release_tar_path()

    cond do
      File.exists?(tar_path) and not force? ->
        Mix.shell().info(
          "Tarball already exists for #{version}, skipping build (use --force to rebuild)"
        )

      true ->
        Mix.shell().info("Building release #{app_name} #{version}...")
        Mix.shell().info("running `mix assets.deploy`...")
        Mix.Task.run("assets.deploy", [])
        Mix.shell().info("running `mix release`...")
        Mix.Task.run("release", [])
    end

    unless File.exists?(tar_path) do
      Mix.raise("""
      Release tarball not found: #{tar_path}
      Make sure your release config produces a tarball (include `include_erts: true`).
      """)
    end

    if publish? and publishers != [] do
      Mix.shell().info("Publishing #{app_name} #{version}...")

      case Sysd.Publisher.publish_all(publishers, tar_path, app_name, version, replace: replace?) do
        {:ok, urls} ->
          Enum.each(urls, fn
            nil -> :ok
            url -> Mix.shell().info("  published: #{url}")
          end)

        {:error, reason} ->
          Mix.raise("Publish failed: #{reason}")
      end
    else
      if publishers == [] do
        Mix.shell().info("No publishers configured; local build only.")
      else
        Mix.shell().info("--no-publish set; skipping publishers.")
      end
    end
  end
end
