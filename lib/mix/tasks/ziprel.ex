defmodule Mix.Tasks.Ziprel do
  @shortdoc "Display Ziprel help"

  @moduledoc """
  Display an overview of all available Ziprel Mix tasks.

      $ mix ziprel

  ## Available Tasks

  | Task                           | Description                          |
  | ------------------------------ | ------------------------------------ |
  | `mix ziprel`                   | This help message                    |
  | `mix ziprel.init`              | Generate config stubs                |
  | `mix ziprel.sshcheck`          | Check SSH connection and permissions |
  | `mix ziprel.setup`             | Setup servers for deployment         |
  | `mix ziprel.deploy`            | Deploy app to servers                |
  | `mix ziprel.versions`          | List release versions on servers     |
  | `mix ziprel.rollback VERSION`  | Rollback to a previous version       |
  | `mix ziprel.remove VERSION`    | Remove old releases                  |
  | `mix ziprel.cleanup SERVER`    | Remove everything from server        |

  Run `mix help ziprel.<task>` for detailed help on any task.
  """
  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("""
    Ziprel - Deploy Elixir releases to bare metal servers

    Mix Tasks:
      mix ziprel                     This help message
      mix ziprel.init                Generate config stubs
      mix ziprel.sshcheck            Check SSH connection and permissions
      mix ziprel.setup               Setup servers for deployment
      mix ziprel.deploy              Deploy app to servers
      mix ziprel.versions            List release versions on servers
      mix ziprel.rollback [VERSION]  Rollback to a previous version
      mix ziprel.remove [VERSION]    Remove old releases
      mix ziprel.cleanup [SERVER]    Remove everything from server
    """)
  end
end
