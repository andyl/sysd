defmodule Mix.Tasks.Reldep.Versions do
  @shortdoc "List release versions on servers"

  @moduledoc """
  List deployed release versions on all configured servers.

      $ mix reldep.versions

  For each server in `config/reldep.yaml`, lists every version found
  under `/opt/reldep/<appname>/releases/`. The currently active version (the
  target of the `/opt/reldep/<appname>/current` symlink) is marked with
  `(current)`.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    config = RelDep.Config.load()
    app_name = RelDep.app_name()

    Enum.each(config.servers, fn server ->
      Mix.shell().info("#{server}:")

      case RelDep.Deploy.versions(server, app: app_name, config: config) do
        {:ok, %{versions: versions, current: current}} ->
          if Enum.empty?(versions) do
            Mix.shell().info("  No versions found")
          else
            Enum.each(versions, fn ver ->
              marker = if ver == current, do: " (current)", else: ""
              Mix.shell().info("  #{ver}#{marker}")
            end)
          end

        {:error, reason} ->
          Mix.shell().error("  Error: #{inspect(reason)}")
      end
    end)
  end
end
