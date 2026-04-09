defmodule Sysd.Config do
  @moduledoc """
  Reads, writes, and manipulates the Sysd YAML configuration.

  ## Config Precedence (for `load/1`)

  1. Explicit `:config_path` option (from `--config` CLI flag)
  2. `SYSD_CONFIG_FILE` environment variable
  3. Walk up from cwd looking for `sysd.yml`
  4. XDG fallback: `~/.config/sysd/config.yml`

  The legacy `load/0` preserves backward compatibility by loading from
  `config/sysd.yaml` (the hardcoded Mix project path).

  ## Config Shapes

  **Legacy (single-app):**

      servers:
        - host1
      ssh:
        user: deploy

  **Multi-app:**

      apps:
        myapp:
          servers:
            - host1
          ssh:
            user: deploy

  ## Struct Fields

    * `:servers` — list of hostname strings
    * `:ssh` — map of SSH options (e.g. `%{user: "deploy"}`)
    * `:app` — app name (set when loading multi-app config)
    * `:instances` — map of hostname to list of instance configs,
      e.g. `%{"host1" => [%{name: "inst1", env: %{"PORT" => "4001"}}]}`
  """

  defstruct servers: [], ssh: %{}, app: nil, instances: %{}

  @legacy_config_path "config/sysd.yaml"
  @walk_up_filename "sysd.yml"

  @doc "Returns the legacy path to the YAML config file."
  def config_path, do: @legacy_config_path

  @doc """
  Load config from the legacy hardcoded path (`config/sysd.yaml`).

  Preserved for backward compatibility with existing Mix tasks.
  Raises a `Mix.Error` if the file does not exist.
  """
  def load do
    path = @legacy_config_path

    unless File.exists?(path) do
      Mix.raise("Config file not found: #{path}\nRun `mix sysd.init` to generate it.")
    end

    data = YamlElixir.read_from_file!(path)
    parse(data)
  end

  @doc """
  Load config using the four-level precedence chain.

  ## Options

    * `:config_path` — explicit path (highest priority)
    * `:app` — app name to select from a multi-app config

  Returns `{:ok, config}` or `{:error, reason}`.
  """
  def load(opts) when is_list(opts) do
    explicit = Keyword.get(opts, :config_path)
    app = Keyword.get(opts, :app)

    case resolve_config_path(explicit) do
      {:ok, path} ->
        data = YamlElixir.read_from_file!(path)
        config = parse_with_app(data, app)
        {:ok, config}

      {:error, _} = err ->
        err
    end
  end

  defp resolve_config_path(explicit) when is_binary(explicit) do
    if File.exists?(explicit) do
      {:ok, explicit}
    else
      {:error, "config file not found: #{explicit}"}
    end
  end

  defp resolve_config_path(nil) do
    cond do
      env = System.get_env("SYSD_CONFIG_FILE") ->
        if File.exists?(env) do
          {:ok, env}
        else
          {:error, "SYSD_CONFIG_FILE points to missing file: #{env}"}
        end

      path = walk_up_find(@walk_up_filename) ->
        {:ok, path}

      path = xdg_config_path() ->
        if File.exists?(path), do: {:ok, path}, else: {:error, "no config file found"}

      true ->
        {:error, "no config file found"}
    end
  end

  defp walk_up_find(filename) do
    walk_up_find(File.cwd!(), filename)
  end

  defp walk_up_find(dir, filename) do
    candidate = Path.join(dir, filename)

    cond do
      File.exists?(candidate) -> candidate
      dir == "/" -> nil
      true -> walk_up_find(Path.dirname(dir), filename)
    end
  end

  defp xdg_config_path do
    base = System.get_env("XDG_CONFIG_HOME") || Path.join(System.user_home!(), ".config")
    Path.join([base, "sysd", "config.yml"])
  end

  @doc """
  Normalize a raw YAML map into a `%Sysd.Config{}` struct.

  Exposed so tests (and callers that already have parsed YAML) can
  exercise the parsing rules without round-tripping through disk.
  """
  def parse(data) when is_map(data) do
    raw_servers = data["servers"] || []
    {hostnames, instances} = parse_servers(raw_servers)

    %__MODULE__{
      servers: hostnames,
      ssh: Map.new(data["ssh"] || %{}, fn {k, v} -> {String.to_atom(k), v} end),
      instances: instances
    }
  end

  @doc """
  Return the list of instance configs for a given host.

  Each instance is `%{name: String.t(), env: %{String.t() => String.t()}}`.
  Returns `[]` when the host has no instances defined (legacy mode).
  """
  def instances_for_host(%__MODULE__{instances: instances}, host) do
    Map.get(instances, host, [])
  end

  @doc """
  Return the systemd service names for a host.

  With instances: `["sysd_inst1", "sysd_inst2"]`.
  Without instances (legacy): `[app_name]`.
  """
  def service_names(%__MODULE__{} = config, host, app_name) do
    case instances_for_host(config, host) do
      [] -> [to_string(app_name)]
      instances -> Enum.map(instances, &"sysd_#{&1.name}")
    end
  end

  defp parse_servers(servers) do
    Enum.reduce(servers, {[], %{}}, fn entry, {hosts, inst_map} ->
      case entry do
        host when is_binary(host) ->
          {hosts ++ [host], inst_map}

        %{"host" => host} = map ->
          instances =
            (map["instances"] || [])
            |> Enum.map(fn inst ->
              %{
                name: inst["instance_name"],
                env: parse_env_vars(inst["environment_variables"] || %{})
              }
            end)

          inst_map =
            if instances == [],
              do: inst_map,
              else: Map.put(inst_map, host, instances)

          {hosts ++ [host], inst_map}
      end
    end)
  end

  defp parse_env_vars(vars) when is_map(vars) do
    Map.new(vars, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp parse_with_app(data, app) when is_binary(app) do
    case data["apps"] do
      %{^app => app_data} when is_map(app_data) ->
        config = parse(app_data)
        %{config | app: app}

      _ ->
        parse(data)
    end
  end

  defp parse_with_app(data, nil), do: parse(data)

  @doc """
  Write a `%Sysd.Config{}` struct back to the YAML config file.

  Creates the parent directory if it does not exist.
  """
  def write(%__MODULE__{} = config) do
    yaml =
      """
      servers:
      #{Enum.map_join(config.servers, "\n", &"  - #{&1}")}
      ssh:
        user: #{config.ssh[:user]}
      """

    File.mkdir_p!(Path.dirname(@legacy_config_path))
    File.write!(@legacy_config_path, yaml)
  end

  @doc """
  Remove a server from the config and write the updated file.

  Returns the updated `%Sysd.Config{}` struct.
  """
  def remove_server(%__MODULE__{} = config, server) do
    updated = %{config | servers: Enum.reject(config.servers, &(&1 == server))}
    write(updated)
    updated
  end
end
