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

  ## Struct Fields

    * `:servers` — list of hostname strings
    * `:ssh` — map of SSH options (e.g. `%{user: "deploy"}`)
  """

  defstruct servers: [], ssh: %{}

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

    %__MODULE__{
      servers: data["servers"] || [],
      ssh: Map.new(data["ssh"] || %{}, fn {k, v} -> {String.to_atom(k), v} end)
    }
  end

  @doc """
  Write a `%Relman.Config{}` struct back to the YAML config file.

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
end
