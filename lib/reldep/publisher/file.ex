defmodule RelDep.Publisher.File do
  @moduledoc """
  Publisher that copies the release tarball to a local or mounted
  filesystem directory.

  Useful for publishing to an NFS share, a directory served by a
  static web server, or just a local archive folder. Config:

      release:
        publish:
          - type: file
            path: /mnt/releases/myapp/

  ## Preflight

    * `path` is set and absolute.
    * `path` exists and is a writable directory — it is **not**
      auto-created, because silently creating a typo'd destination is
      worse than failing loudly.
    * No file named `<app>-<version>.tar.gz` already exists at `path`
      unless `--replace` was passed.

  ## Publish / Fetch

  `publish/4` copies the local tarball to `<path>/<app>-<version>.tar.gz`.
  `fetch/4` copies the same file back into the expected build location.
  """

  @behaviour RelDep.Publisher

  @impl true
  def preflight(%{path: nil}), do: {:error, "`path` is required"}
  def preflight(%{path: ""}), do: {:error, "`path` is required"}

  def preflight(%{path: path} = spec) do
    cond do
      not is_binary(path) ->
        {:error, "`path` must be a string"}

      Path.type(path) != :absolute ->
        {:error, "`path` must be an absolute path, got #{inspect(path)}"}

      not File.dir?(path) ->
        {:error, "`path` does not exist or is not a directory: #{path}"}

      not writable?(path) ->
        {:error, "`path` is not writable: #{path}"}

      true ->
        check_existing(spec)
    end
  end

  def preflight(_), do: {:error, "`path` is required"}

  defp check_existing(%{path: path} = spec) do
    # App/version are not known at preflight time. The collision check
    # happens in publish/4 where they are available — we still verify
    # here that the directory is writable, which covers the common
    # misconfiguration case.
    _ = path
    _ = spec
    :ok
  end

  defp writable?(path) do
    probe = Path.join(path, ".reldep_write_probe")

    case File.write(probe, "") do
      :ok ->
        _ = File.rm(probe)
        true

      _ ->
        false
    end
  end

  @impl true
  def publish(%{path: path} = spec, tar, app, version) do
    dest = target_path(path, app, version)
    replace? = Map.get(spec, :replace, false)

    cond do
      File.exists?(dest) and not replace? ->
        {:error, "artifact already exists at #{dest} (pass --replace to overwrite)"}

      true ->
        case File.cp(tar, dest) do
          :ok -> {:ok, "file://#{dest}"}
          {:error, reason} -> {:error, "copy to #{dest} failed: #{inspect(reason)}"}
        end
    end
  end

  @impl true
  def fetch(%{path: path}, app, version, dest_dir) do
    src = target_path(path, app, version)

    cond do
      not File.exists?(src) ->
        {:error, "no artifact at #{src}"}

      true ->
        File.mkdir_p!(dest_dir)
        dest = Path.join(dest_dir, "#{app}-#{version}.tar.gz")

        case File.cp(src, dest) do
          :ok -> {:ok, "file://#{src}"}
          {:error, reason} -> {:error, "copy from #{src} failed: #{inspect(reason)}"}
        end
    end
  end

  @doc false
  def target_path(path, app, version) do
    path
    |> Path.expand()
    |> Path.join("#{app}-#{version}.tar.gz")
  end
end
