defmodule Mix.Tasks.Reldep.Remove do
  @shortdoc "Remove old releases"

  @moduledoc """
  Remove an old release version from all configured servers.

      $ mix reldep.remove VERSION

  For each server in `config/reldep.yaml`, this task will delete:

    * `/opt/reldep/<appname>/releases/<VERSION>/`
    * `/opt/reldep/<appname>/archives/<VERSION>.tar.gz`

  The currently active version cannot be removed. Use
  `mix reldep.versions` to check which version is current, and
  `mix reldep.rollback` to switch away from it first if needed.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case args do
      [version] ->
        config = RelDep.Config.load()
        app_name = RelDep.app_name()

        Enum.each(config.servers, fn server ->
          Mix.shell().info("Removing #{version} from #{server}...")

          case RelDep.Deploy.remove(server, version, app: app_name, config: config) do
            {:ok, :removed} ->
              Mix.shell().info("  Removed successfully")

            {:error, reason} ->
              Mix.raise("Remove failed on #{server}: #{reason}")
          end
        end)

      _ ->
        Mix.raise("Usage: mix reldep.remove VERSION")
    end
  end
end
