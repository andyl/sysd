defmodule Mix.Tasks.Sysd.Remove do
  @shortdoc "Remove old releases"

  @moduledoc """
  Remove an old release version from all configured servers.

      $ mix sysd.remove VERSION

  For each server in `config/sysd.yaml`, this task will delete:

    * `/opt/sysd/<appname>/releases/<VERSION>/`
    * `/opt/sysd/<appname>/archives/<VERSION>.tar.gz`

  The currently active version cannot be removed. Use
  `mix sysd.versions` to check which version is current, and
  `mix sysd.rollback` to switch away from it first if needed.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case args do
      [version] ->
        config = Sysd.Config.load()
        app_name = Sysd.app_name()

        Enum.each(config.servers, fn server ->
          Mix.shell().info("Removing #{version} from #{server}...")

          case Sysd.Deploy.remove(server, version, app: app_name, config: config) do
            {:ok, :removed} ->
              Mix.shell().info("  Removed successfully")

            {:error, reason} ->
              Mix.raise("Remove failed on #{server}: #{reason}")
          end
        end)

      _ ->
        Mix.raise("Usage: mix sysd.remove VERSION")
    end
  end
end
