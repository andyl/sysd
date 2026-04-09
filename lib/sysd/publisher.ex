defmodule Sysd.Publisher do
  @moduledoc """
  Pluggable publisher behaviour and dispatch for `mix sysd.release`.

  A publisher is an external artifact store (GitHub Releases, an NFS
  share, a local directory, ...) that sysd can push a release
  tarball to and later pull it back from. Publishers are declared as
  an ordered list under `release.publish` in `config/sysd.yaml` and
  normalized into spec maps by `Sysd.Config`.

  Each publisher implementation is a module implementing this
  behaviour. The three callbacks form a small contract:

    * `preflight/1` — validate configuration and environment before
      any build work runs. Called up front so misconfiguration fails
      fast.
    * `publish/4` — upload or copy the tarball to the destination.
    * `fetch/4` — retrieve a previously published tarball into the
      local build directory (used by `sysd.deploy --from-release`).

  The `opts` on the spec map may include a `:replace` boolean — set
  by the task layer when `--replace` was passed on the CLI. Publisher
  implementations should honor it in `preflight/1` and `publish/4`.

  ## Resolving a spec

  `resolve/1` maps a spec `%{type: :github, ...}` to the
  implementation module. Task code never branches on the publisher
  `:type` directly — it iterates over specs and dispatches here.
  """

  @type spec :: %{required(:type) => atom(), optional(atom()) => any()}

  @callback preflight(spec) :: :ok | {:error, String.t()}
  @callback publish(spec, tar :: Path.t(), app :: atom(), version :: String.t()) ::
              {:ok, String.t() | nil} | {:error, String.t()}
  @callback fetch(spec, app :: atom(), version :: String.t(), dest :: Path.t()) ::
              {:ok, String.t() | nil} | {:error, String.t()}

  @doc """
  Return the publisher implementation module for a spec.

  A `:module` override on the spec map wins, which is how the test
  suite injects a stub publisher without touching application env.
  Otherwise the `:type` atom is mapped to a concrete module.
  """
  def resolve(%{module: module}) when is_atom(module) and not is_nil(module), do: module
  def resolve(%{type: :github}), do: Sysd.Publisher.Github
  def resolve(%{type: :file}), do: Sysd.Publisher.File

  def resolve(%{type: other}) do
    Mix.raise("No publisher implementation for type #{inspect(other)}")
  end

  @doc """
  Run `preflight/1` on every spec. Returns `:ok` or
  `{:error, [reason, ...]}` with every failure collected, so the user
  sees all misconfiguration at once.
  """
  def preflight_all(specs, opts \\ []) do
    specs = with_opts(specs, opts)

    errors =
      specs
      |> Enum.map(fn spec ->
        module = resolve(spec)

        case module.preflight(spec) do
          :ok -> :ok
          {:error, reason} -> {:error, "#{inspect(module)}: #{reason}"}
        end
      end)
      |> Enum.filter(&match?({:error, _}, &1))
      |> Enum.map(fn {:error, r} -> r end)

    case errors do
      [] -> :ok
      errs -> {:error, errs}
    end
  end

  @doc """
  Run `publish/4` on every spec in order. Stops on the first error.
  Returns `{:ok, [url_or_nil, ...]}` or `{:error, reason}`.
  """
  def publish_all(specs, tar, app, version, opts \\ []) do
    specs = with_opts(specs, opts)

    Enum.reduce_while(specs, {:ok, []}, fn spec, {:ok, urls} ->
      module = resolve(spec)

      case module.publish(spec, tar, app, version) do
        {:ok, url} -> {:cont, {:ok, [url | urls]}}
        {:error, reason} -> {:halt, {:error, "#{inspect(module)}: #{reason}"}}
      end
    end)
    |> case do
      {:ok, urls} -> {:ok, Enum.reverse(urls)}
      other -> other
    end
  end

  @doc """
  Walk publisher specs in order and return the first successful
  `fetch/4`. Returns `{:ok, url_or_nil}` on success, or
  `{:error, [reason, ...]}` if every publisher failed.
  """
  def fetch_first(specs, app, version, dest, opts \\ []) do
    specs = with_opts(specs, opts)

    Enum.reduce_while(specs, {:error, []}, fn spec, {:error, errs} ->
      module = resolve(spec)

      case module.fetch(spec, app, version, dest) do
        {:ok, url} -> {:halt, {:ok, url}}
        {:error, reason} -> {:cont, {:error, ["#{inspect(module)}: #{reason}" | errs]}}
      end
    end)
    |> case do
      {:ok, url} -> {:ok, url}
      {:error, errs} -> {:error, Enum.reverse(errs)}
    end
  end

  defp with_opts(specs, []), do: specs

  defp with_opts(specs, opts) do
    opts_map = Map.new(opts)
    Enum.map(specs, &Map.merge(&1, opts_map))
  end
end
