defmodule Mix.Tasks.Sysd do
  @shortdoc "Display Sysd help"

  @moduledoc """
  Display an overview of all available Sysd Mix tasks.

      $ mix sysd

  ## Available Tasks

  | Task                           | Description                          |
  | ------------------------------ | ------------------------------------ |
  | `mix sysd`                   | This help message                    |
  | `mix sysd.init`              | Generate config stubs                |
  | `mix sysd.sshcheck`          | Check SSH connection and permissions |
  | `mix sysd.setup`             | Setup servers for deployment         |
  | `mix sysd.release`           | Build release tarball and publish    |
  | `mix sysd.deploy`            | Deploy a release to servers          |
  | `mix sysd.versions`          | List release versions on servers     |
  | `mix sysd.rollback VERSION`  | Rollback to a previous version       |
  | `mix sysd.remove VERSION`    | Remove old releases                  |
  | `mix sysd.cleanup SERVER`    | Remove everything from server        |

  Run `mix help sysd.<task>` for detailed help on any task.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("""
    Sysd - Deploy Elixir releases to bare metal servers

    Mix Tasks:
      mix sysd                     This help message
      mix sysd.init                Generate config stubs
      mix sysd.sshcheck            Check SSH connection and permissions
      mix sysd.setup               Setup servers for deployment
      mix sysd.release             Build release tarball and publish
      mix sysd.deploy              Deploy a release to servers
      mix sysd.versions            List release versions on servers
      mix sysd.rollback [VERSION]  Rollback to a previous version
      mix sysd.remove [VERSION]    Remove old releases
      mix sysd.cleanup [SERVER]    Remove everything from server
    """)
  end
end
