defmodule Mix.Tasks.Reldep do
  @shortdoc "Display RelDep help"

  @moduledoc """
  Display an overview of all available RelDep Mix tasks.

      $ mix reldep

  ## Available Tasks

  | Task                           | Description                          |
  | ------------------------------ | ------------------------------------ |
  | `mix reldep`                   | This help message                    |
  | `mix reldep.init`              | Generate config stubs                |
  | `mix reldep.sshcheck`          | Check SSH connection and permissions |
  | `mix reldep.setup`             | Setup servers for deployment         |
  | `mix reldep.release`           | Build release tarball and publish    |
  | `mix reldep.deploy`            | Deploy a release to servers          |
  | `mix reldep.versions`          | List release versions on servers     |
  | `mix reldep.rollback VERSION`  | Rollback to a previous version       |
  | `mix reldep.remove VERSION`    | Remove old releases                  |
  | `mix reldep.cleanup SERVER`    | Remove everything from server        |

  Run `mix help reldep.<task>` for detailed help on any task.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("""
    RelDep - Deploy Elixir releases to bare metal servers

    Mix Tasks:
      mix reldep                     This help message
      mix reldep.init                Generate config stubs
      mix reldep.sshcheck            Check SSH connection and permissions
      mix reldep.setup               Setup servers for deployment
      mix reldep.release             Build release tarball and publish
      mix reldep.deploy              Deploy a release to servers
      mix reldep.versions            List release versions on servers
      mix reldep.rollback [VERSION]  Rollback to a previous version
      mix reldep.remove [VERSION]    Remove old releases
      mix reldep.cleanup [SERVER]    Remove everything from server
    """)
  end
end
