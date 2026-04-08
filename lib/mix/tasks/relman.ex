defmodule Mix.Tasks.Relman do
  @shortdoc "Display Relman help"

  @moduledoc """
  Display an overview of all available Relman Mix tasks.

      $ mix relman

  ## Available Tasks

  | Task                           | Description                          |
  | ------------------------------ | ------------------------------------ |
  | `mix relman`                   | This help message                    |
  | `mix relman.init`              | Generate config stubs                |
  | `mix relman.sshcheck`          | Check SSH connection and permissions |
  | `mix relman.setup`             | Setup servers for deployment         |
  | `mix relman.release`           | Build release tarball and publish    |
  | `mix relman.deploy`            | Deploy a release to servers          |
  | `mix relman.versions`          | List release versions on servers     |
  | `mix relman.rollback VERSION`  | Rollback to a previous version       |
  | `mix relman.remove VERSION`    | Remove old releases                  |
  | `mix relman.cleanup SERVER`    | Remove everything from server        |

  Run `mix help relman.<task>` for detailed help on any task.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("""
    Relman - Deploy Elixir releases to bare metal servers

    Mix Tasks:
      mix relman                     This help message
      mix relman.init                Generate config stubs
      mix relman.sshcheck            Check SSH connection and permissions
      mix relman.setup               Setup servers for deployment
      mix relman.release             Build release tarball and publish
      mix relman.deploy              Deploy a release to servers
      mix relman.versions            List release versions on servers
      mix relman.rollback [VERSION]  Rollback to a previous version
      mix relman.remove [VERSION]    Remove old releases
      mix relman.cleanup [SERVER]    Remove everything from server
    """)
  end
end
