defmodule Relman.Config do
  @moduledoc """
  Reads, writes, and manipulates the Relman YAML configuration.

  The config file lives at `config/relman.yaml` in the consumer project
  and has this structure:

      servers:
        - host1
        - host2
      ssh:
        user: deploy
      release:
        publish:
          - type: github
            draft: false
            prerelease: false
          - type: file
            path: /mnt/releases/myapp/

  ## Struct Fields

    * `:servers` — list of hostname strings
    * `:ssh` — map of SSH options (e.g. `%{user: "deploy"}`)
    * `:release` — map with a `:publish` key holding the ordered list
      of normalized publisher spec maps (see `parse/1`)

  ## Publisher Specs

  Each entry under `release.publish` is normalized into a map with
  atom keys. The currently supported types are:

    * `%{type: :github, draft: boolean, prerelease: boolean}`
    * `%{type: :file, path: String.t()}`

  Note that `write/1` does not round-trip the `release.publish` block.
  It only rewrites the fields it manages directly (servers + ssh).
  Users add or edit the `release.publish` section by hand.
  """

  defstruct servers: [], ssh: %{}, release: %{publish: []}

  @config_path "config/relman.yaml"

  @doc "Returns the path to the YAML config file."
  def config_path, do: @config_path

  @doc """
  Load and parse the YAML config file into a `%Relman.Config{}` struct.

  Raises a `Mix.Error` if the file does not exist.
  """
  def load do
    path = @config_path

    unless File.exists?(path) do
      Mix.raise("Config file not found: #{path}\nRun `mix relman.init` to generate it.")
    end

    data = YamlElixir.read_from_file!(path)
    parse(data)
  end

  @doc """
  Normalize a raw YAML map into a `%Relman.Config{}` struct.

  Exposed so tests (and callers that already have parsed YAML) can
  exercise the parsing rules without round-tripping through disk.
  """
  def parse(data) when is_map(data) do
    %__MODULE__{
      servers: data["servers"] || [],
      ssh: Map.new(data["ssh"] || %{}, fn {k, v} -> {String.to_atom(k), v} end),
      release: %{publish: parse_publishers(get_in(data, ["release", "publish"]) || [])}
    }
  end

  defp parse_publishers(list) when is_list(list) do
    Enum.map(list, &parse_publisher/1)
  end

  defp parse_publisher(%{"type" => "github"} = entry) do
    %{
      type: :github,
      draft: Map.get(entry, "draft", false),
      prerelease: Map.get(entry, "prerelease", false)
    }
  end

  defp parse_publisher(%{"type" => "file"} = entry) do
    %{
      type: :file,
      path: Map.get(entry, "path")
    }
  end

  defp parse_publisher(%{"type" => other}) do
    Mix.raise("Unknown publisher type in config/relman.yaml: #{inspect(other)}")
  end

  defp parse_publisher(other) do
    Mix.raise("Invalid publisher entry in config/relman.yaml: #{inspect(other)}")
  end

  @doc """
  Write a `%Relman.Config{}` struct back to the YAML config file.

  Creates the parent directory if it does not exist. Note: this does
  **not** round-trip the `release.publish` block. Any existing publisher
  configuration in the file on disk will be lost. Only the fields that
  relman manages programmatically (servers, ssh) are rewritten.
  """
  def write(%__MODULE__{} = config) do
    yaml =
      """
      servers:
      #{Enum.map_join(config.servers, "\n", &"  - #{&1}")}
      ssh:
        user: #{config.ssh[:user]}
      """

    File.mkdir_p!(Path.dirname(@config_path))
    File.write!(@config_path, yaml)
  end

  @doc """
  Remove a server from the config and write the updated file.

  Returns the updated `%Relman.Config{}` struct.
  """
  def remove_server(%__MODULE__{} = config, server) do
    updated = %{config | servers: Enum.reject(config.servers, &(&1 == server))}
    write(updated)
    updated
  end

  @doc """
  Return the ordered list of publisher specs from a loaded config.
  """
  def publishers(%__MODULE__{release: %{publish: list}}), do: list
  def publishers(%__MODULE__{}), do: []
end
