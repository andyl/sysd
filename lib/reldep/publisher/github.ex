defmodule RelDep.Publisher.Github do
  @moduledoc """
  Publisher that uploads a release tarball to GitHub Releases via
  the `gh` CLI.

  Using `gh` rather than a native HTTP client keeps auth, retries,
  and multipart upload out of this codebase, and most users who want
  to publish to GitHub already have `gh` installed.

  Config:

      release:
        publish:
          - type: github
            draft: false
            prerelease: false

  ## Preflight

    1. `gh` executable is on `$PATH`.
    2. `gh auth status` exits 0.
    3. `git remote get-url origin` points at `github.com` (both
       `https://` and `git@` forms are accepted) and yields an
       `owner/repo` pair.
    4. Local git tag `v<version>` exists.
    5. No GitHub release exists yet for `v<version>` unless
       `--replace` was passed (in which case the existing release is
       deleted in `publish/4`).

  ## Publish / Fetch

  `publish/4` runs `gh release create v<version> <tarball>` with an
  auto-generated title (`<app> v<version>`) and an empty body. The
  `draft` and `prerelease` options are honored. Release notes sourcing
  is deferred — see the design doc.

  `fetch/4` runs `gh release download v<version> --pattern ...` into
  the expected local build directory.
  """

  @behaviour RelDep.Publisher

  alias RelDep.Publisher.Github.Util

  @impl true
  def preflight(spec) do
    version = RelDep.version()
    tag = "v#{version}"

    with :ok <- check_gh_installed(),
         :ok <- check_gh_auth(),
         {:ok, _repo} <- Util.origin_repo(origin_url()),
         :ok <- check_tag(tag),
         :ok <- check_existing_release(tag, Map.get(spec, :replace, false)) do
      :ok
    end
  end

  defp check_gh_installed do
    if System.find_executable("gh"),
      do: :ok,
      else: {:error, "`gh` executable not found on $PATH"}
  end

  defp check_gh_auth do
    case System.cmd("gh", ["auth", "status"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, "gh auth status failed: #{String.trim(output)}"}
    end
  end

  defp origin_url do
    case System.cmd("git", ["remote", "get-url", "origin"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> ""
    end
  end

  defp check_tag(tag) do
    if RelDep.git_tag_exists?(tag),
      do: :ok,
      else: {:error, "git tag #{tag} does not exist locally"}
  end

  defp check_existing_release(tag, replace?) do
    case System.cmd("gh", ["release", "view", tag], stderr_to_stdout: true) do
      {_, 0} ->
        if replace?,
          do: :ok,
          else: {:error, "GitHub release #{tag} already exists (pass --replace to overwrite)"}

      _ ->
        :ok
    end
  end

  @impl true
  def publish(spec, tar, app, version) do
    tag = "v#{version}"
    replace? = Map.get(spec, :replace, false)

    with :ok <- maybe_delete_release(tag, replace?),
         :ok <- gh_release_create(spec, tag, tar, app, version) do
      case Util.origin_repo(origin_url()) do
        {:ok, repo} ->
          {:ok, "https://github.com/#{repo}/releases/tag/#{tag}"}

        _ ->
          {:ok, nil}
      end
    end
  end

  defp maybe_delete_release(_tag, false), do: :ok

  defp maybe_delete_release(tag, true) do
    case System.cmd("gh", ["release", "delete", tag, "--yes"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, _} ->
        # If the release doesn't exist, `gh` returns non-zero with
        # "release not found" — swallow that so --replace is idempotent.
        if output =~ "not found" or output =~ "release not found" do
          :ok
        else
          {:error, "gh release delete failed: #{String.trim(output)}"}
        end
    end
  end

  defp gh_release_create(spec, tag, tar, app, version) do
    args = Util.release_create_args(spec, tag, tar, app, version)

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, status} -> {:error, "gh release create failed (#{status}): #{String.trim(output)}"}
    end
  end

  @impl true
  def fetch(_spec, app, version, dest_dir) do
    tag = "v#{version}"
    pattern = "#{app}-#{version}.tar.gz"
    File.mkdir_p!(dest_dir)

    args = ["release", "download", tag, "--pattern", pattern, "--dir", dest_dir]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {_, 0} ->
        case Util.origin_repo(origin_url()) do
          {:ok, repo} -> {:ok, "https://github.com/#{repo}/releases/tag/#{tag}"}
          _ -> {:ok, nil}
        end

      {output, status} ->
        {:error, "gh release download failed (#{status}): #{String.trim(output)}"}
    end
  end
end

defmodule RelDep.Publisher.Github.Util do
  @moduledoc false

  @doc """
  Parse a GitHub origin URL into `{:ok, "owner/repo"}`.

  Handles both forms:
    * `https://github.com/owner/repo(.git)?`
    * `git@github.com:owner/repo(.git)?`
  """
  def origin_repo(url) when is_binary(url) do
    url = String.trim(url)

    cond do
      url == "" ->
        {:error, "could not determine origin remote (is this a git repo with a GitHub origin?)"}

      match = Regex.run(~r{^https?://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$}, url) ->
        [_, owner, repo] = match
        {:ok, "#{owner}/#{repo}"}

      match = Regex.run(~r{^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?/?$}, url) ->
        [_, owner, repo] = match
        {:ok, "#{owner}/#{repo}"}

      true ->
        {:error, "origin is not a github.com URL: #{url}"}
    end
  end

  @doc """
  Build the `gh release create` argv list for the given inputs.

  Pure function — tests exercise this directly.
  """
  def release_create_args(spec, tag, tar, app, version) do
    base = [
      "release",
      "create",
      tag,
      tar,
      "--title",
      "#{app} v#{version}",
      "--notes",
      ""
    ]

    base
    |> maybe_append(spec[:draft], "--draft")
    |> maybe_append(spec[:prerelease], "--prerelease")
  end

  defp maybe_append(args, true, flag), do: args ++ [flag]
  defp maybe_append(args, _, _), do: args
end
