defmodule RelDep.TarballRef do
  @moduledoc """
  Parse and resolve tarball reference strings.

  Supported schemes:

    * `file:///path/to/app.tar.gz` — local file path
    * `gh://owner/repo@tag` — GitHub release asset via `gh` CLI
    * `s3://bucket/key` — S3 object (not yet implemented)
    * bare path (`/path/to/app.tar.gz`) — treated as local file

  Use `parse/1` to parse a reference string into a `%TarballRef{}` struct,
  then `resolve/2` to materialize it to a local file path.
  """

  defstruct [:scheme, :path, :owner, :repo, :tag]

  @type t :: %__MODULE__{
          scheme: :file | :github | :s3,
          path: String.t() | nil,
          owner: String.t() | nil,
          repo: String.t() | nil,
          tag: String.t() | nil
        }

  @doc """
  Parse a tarball reference string into a `%TarballRef{}`.

  Returns `{:ok, ref}` or `{:error, reason}`.
  """
  def parse("file://" <> path) do
    {:ok, %__MODULE__{scheme: :file, path: path}}
  end

  def parse("gh://" <> rest) do
    case String.split(rest, "@", parts: 2) do
      [repo_part, tag] ->
        case String.split(repo_part, "/", parts: 2) do
          [owner, repo] ->
            {:ok, %__MODULE__{scheme: :github, owner: owner, repo: repo, tag: tag}}

          _ ->
            {:error, "invalid gh:// ref: expected gh://owner/repo@tag, got gh://#{rest}"}
        end

      _ ->
        {:error, "invalid gh:// ref: missing @tag in gh://#{rest}"}
    end
  end

  def parse("s3://" <> rest) do
    {:ok, %__MODULE__{scheme: :s3, path: rest}}
  end

  def parse("/" <> _ = path) do
    {:ok, %__MODULE__{scheme: :file, path: path}}
  end

  def parse(path) when is_binary(path) and byte_size(path) > 0 do
    {:ok, %__MODULE__{scheme: :file, path: path}}
  end

  def parse(_) do
    {:error, "invalid tarball reference"}
  end

  @doc """
  Resolve a `%TarballRef{}` to a local file path.

  For `:file` refs, validates the file exists. For `:github` refs,
  downloads the asset via the `gh` CLI into `dest_dir`.

  Returns `{:ok, local_path}` or `{:error, reason}`.
  """
  def resolve(%__MODULE__{scheme: :file, path: path}, _dest_dir) do
    if File.exists?(path) do
      {:ok, path}
    else
      {:error, "file not found: #{path}"}
    end
  end

  def resolve(%__MODULE__{scheme: :github, owner: owner, repo: repo, tag: tag}, dest_dir) do
    case System.find_executable("gh") do
      nil ->
        {:error, "`gh` CLI not found on $PATH (required for gh:// scheme)"}

      _gh ->
        File.mkdir_p!(dest_dir)
        nwo = "#{owner}/#{repo}"

        args = [
          "release",
          "download",
          tag,
          "--repo",
          nwo,
          "--pattern",
          "*.tar.gz",
          "--dir",
          dest_dir
        ]

        case System.cmd("gh", args, stderr_to_stdout: true) do
          {_output, 0} ->
            find_downloaded(dest_dir, tag)

          {output, _} ->
            {:error, "gh release download failed: #{String.trim(output)}"}
        end
    end
  end

  def resolve(%__MODULE__{scheme: :s3}, _dest_dir) do
    {:error, {:not_implemented, "s3:// scheme"}}
  end

  defp find_downloaded(dest_dir, _tag) do
    case Path.wildcard(Path.join(dest_dir, "*.tar.gz")) do
      [path | _] -> {:ok, path}
      [] -> {:error, "no .tar.gz file found after download in #{dest_dir}"}
    end
  end
end
