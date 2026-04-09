defmodule Sysd.CLI do
  @moduledoc """
  Escript entry point for the `sysd` command-line tool.

  Parses argv with Optimus, dispatches to `Sysd.Deploy.*`,
  formats output, and sets exit codes.
  """

  def main(argv) do
    optimus = build_optimus()

    case Optimus.parse(optimus, argv) do
      :help ->
        IO.puts(Optimus.help(optimus))

      :version ->
        IO.puts("sysd #{optimus.version}")

      {:ok, %{args: %{}, flags: %{}, options: %{}}} ->
        IO.puts(Optimus.help(optimus))

      {:help, _subcommand_path} ->
        IO.puts(Optimus.help(optimus))

      {:ok, [:check], parsed} ->
        run_check(parsed)

      {:ok, [:deploy], parsed} ->
        run_deploy(parsed)

      {:ok, [:versions], parsed} ->
        run_versions(parsed)

      {:ok, [:rollback], parsed} ->
        run_rollback(parsed)

      {:ok, [:status], parsed} ->
        run_status(parsed)

      {:ok, [:start], parsed} ->
        run_start(parsed)

      {:ok, [:stop], parsed} ->
        run_stop(parsed)

      {:ok, [:restart], parsed} ->
        run_restart(parsed)

      {:ok, [:tail], parsed} ->
        run_tail(parsed)

      {:ok, [:remove], parsed} ->
        run_remove(parsed)

      {:ok, [:cleanup], parsed} ->
        run_cleanup(parsed)

      {:ok, [:setup], parsed} ->
        run_setup(parsed)

      {:ok, [:systemd], parsed} ->
        run_systemd(parsed)

      {:error, _subcmd, msgs} when is_list(msgs) ->
        Enum.each(msgs, &IO.puts(:stderr, &1))
        System.halt(1)

      {:error, msg} ->
        IO.puts(:stderr, msg)
        System.halt(1)
    end
  end

  defp build_optimus do
    Optimus.new!(
      name: "sysd",
      description: "Deploy Elixir releases to bare metal servers over SSH",
      version: "0.2.1",
      allow_unknown_args: false,
      subcommands: [
        check: [
          name: "check",
          about: "Check SSH connectivity and permissions",
          args: [host: [value_name: "HOST", help: "Server hostname", required: true]],
          options: common_options()
        ],
        setup: [
          name: "setup",
          about: "Setup server directories and install systemd service",
          args: [host: [value_name: "HOST", help: "Server hostname", required: true]],
          options:
            common_options() ++
              [
                user: [
                  value_name: "USER",
                  short: "-u",
                  long: "--user",
                  help: "System user for the service (default: deploy)",
                  required: false
                ]
              ]
        ],
        deploy: [
          name: "deploy",
          about: "Deploy a release tarball to a server",
          args: [
            host: [value_name: "HOST", help: "Server hostname", required: true],
            tarball: [
              value_name: "TARBALL",
              help: "Tarball reference (path, file://, gh://)",
              required: true
            ]
          ],
          options:
            common_options() ++
              [
                version: [
                  value_name: "VERSION",
                  short: "-v",
                  long: "--version",
                  help: "Release version",
                  required: true
                ]
              ]
        ],
        versions: [
          name: "versions",
          about: "List deployed versions on a server",
          args: [host: [value_name: "HOST", help: "Server hostname", required: true]],
          options: common_options()
        ],
        rollback: [
          name: "rollback",
          about: "Rollback to a previous version",
          args: [
            host: [value_name: "HOST", help: "Server hostname", required: true],
            version: [value_name: "VERSION", help: "Target version", required: true]
          ],
          options: common_options()
        ],
        status: [
          name: "status",
          about: "Show systemd service status",
          args: [host: [value_name: "HOST", help: "Server hostname", required: true]],
          options: common_options()
        ],
        start: [
          name: "start",
          about: "Start the systemd service",
          args: [host: [value_name: "HOST", help: "Server hostname", required: true]],
          options: common_options()
        ],
        stop: [
          name: "stop",
          about: "Stop the systemd service",
          args: [host: [value_name: "HOST", help: "Server hostname", required: true]],
          options: common_options()
        ],
        restart: [
          name: "restart",
          about: "Restart the systemd service",
          args: [host: [value_name: "HOST", help: "Server hostname", required: true]],
          options: common_options()
        ],
        tail: [
          name: "tail",
          about: "Tail journal logs (time-bounded)",
          args: [host: [value_name: "HOST", help: "Server hostname", required: true]],
          options:
            common_options() ++
              [
                lines: [
                  value_name: "LINES",
                  short: "-n",
                  long: "--lines",
                  help: "Number of lines (default: 50)",
                  parser: :integer,
                  required: false
                ],
                seconds: [
                  value_name: "SECONDS",
                  short: "-s",
                  long: "--seconds",
                  help: "Duration in seconds (default: 10)",
                  parser: :integer,
                  required: false
                ]
              ]
        ],
        remove: [
          name: "remove",
          about: "Remove a deployed version",
          args: [
            host: [value_name: "HOST", help: "Server hostname", required: true],
            version: [value_name: "VERSION", help: "Version to remove", required: true]
          ],
          options: common_options()
        ],
        cleanup: [
          name: "cleanup",
          about: "Remove all Sysd files from a server",
          args: [host: [value_name: "HOST", help: "Server hostname", required: true]],
          options: common_options()
        ],
        systemd: [
          name: "systemd",
          about: "Generate a systemd service file to stdout",
          options: [
            app: [
              value_name: "APP",
              short: "-a",
              long: "--app",
              help: "Application name",
              required: true
            ],
            user: [
              value_name: "USER",
              short: "-u",
              long: "--user",
              help: "System user (default: deploy)",
              required: false
            ]
          ]
        ]
      ]
    )
  end

  defp common_options do
    [
      app: [
        value_name: "APP",
        short: "-a",
        long: "--app",
        help: "Application name",
        required: true
      ],
      config: [
        value_name: "CONFIG",
        short: "-c",
        long: "--config",
        help: "Path to config file",
        required: false
      ]
    ]
  end

  defp load_config(parsed) do
    config_path = parsed.options[:config]

    case Sysd.Config.load(config_path: config_path) do
      {:ok, config} -> config
      {:error, reason} -> error_exit(reason)
    end
  end

  defp base_opts(parsed) do
    config = load_config(parsed)
    app = parsed.options[:app]
    [app: app, config: config]
  end

  defp run_check(parsed) do
    host = parsed.args.host

    case Sysd.Deploy.check(host, base_opts(parsed)) do
      {:ok, checks} ->
        IO.puts("#{host}:")

        case checks.connection do
          {:ok, user} -> IO.puts("  Connected as #{user}")
          {:error, msg} -> IO.puts("  Connection: FAIL — #{msg}")
        end

        case checks.sudo do
          :ok -> IO.puts("  Sudo: OK")
          {:error, msg} -> IO.puts("  Sudo: FAIL — #{msg}")
        end

        case checks.directory do
          :ok -> IO.puts("  Directory: OK")
          {:error, msg} -> IO.puts("  Directory: FAIL — #{msg}")
        end

      {:error, reason} ->
        error_exit("SSH connection failed: #{inspect(reason)}")
    end
  end

  defp run_deploy(parsed) do
    host = parsed.args.host
    tarball = parsed.args.tarball
    version = parsed.options[:version]
    opts = base_opts(parsed) ++ [version: version]

    IO.puts("Deploying #{version} to #{host}...")

    case Sysd.Deploy.deploy(host, tarball, opts) do
      {:ok, :deployed} -> IO.puts("Deployed successfully")
      {:error, reason} -> error_exit("Deploy failed: #{reason}")
    end
  end

  defp run_versions(parsed) do
    host = parsed.args.host

    case Sysd.Deploy.versions(host, base_opts(parsed)) do
      {:ok, %{versions: versions, current: current}} ->
        IO.puts("#{host}:")

        if Enum.empty?(versions) do
          IO.puts("  No versions found")
        else
          Enum.each(versions, fn ver ->
            marker = if ver == current, do: " (current)", else: ""
            IO.puts("  #{ver}#{marker}")
          end)
        end

      {:error, reason} ->
        error_exit("Failed: #{inspect(reason)}")
    end
  end

  defp run_rollback(parsed) do
    host = parsed.args.host
    version = parsed.args.version

    IO.puts("Rolling back #{host} to #{version}...")

    case Sysd.Deploy.rollback(host, version, base_opts(parsed)) do
      {:ok, :rolled_back} -> IO.puts("Rolled back successfully")
      {:error, reason} -> error_exit("Rollback failed: #{reason}")
    end
  end

  defp run_status(parsed) do
    host = parsed.args.host

    case Sysd.Deploy.status(host, base_opts(parsed)) do
      {:ok, status} -> IO.puts("#{host}: #{status}")
      {:error, reason} -> error_exit("Failed: #{inspect(reason)}")
    end
  end

  defp run_start(parsed) do
    host = parsed.args.host

    case Sysd.Deploy.start(host, base_opts(parsed)) do
      {:ok, :started} -> IO.puts("#{host}: started")
      {:error, reason} -> error_exit("Start failed: #{reason}")
    end
  end

  defp run_stop(parsed) do
    host = parsed.args.host

    case Sysd.Deploy.stop(host, base_opts(parsed)) do
      {:ok, :stopped} -> IO.puts("#{host}: stopped")
      {:error, reason} -> error_exit("Stop failed: #{reason}")
    end
  end

  defp run_restart(parsed) do
    host = parsed.args.host

    case Sysd.Deploy.restart(host, base_opts(parsed)) do
      {:ok, :restarted} -> IO.puts("#{host}: restarted")
      {:error, reason} -> error_exit("Restart failed: #{reason}")
    end
  end

  defp run_tail(parsed) do
    host = parsed.args.host
    lines = parsed.options[:lines] || 50
    seconds = parsed.options[:seconds] || 10
    opts = base_opts(parsed) ++ [lines: lines, seconds: seconds]

    case Sysd.Deploy.tail(host, opts) do
      {:ok, output} -> IO.write(output)
      {:error, reason} -> error_exit("Failed: #{inspect(reason)}")
    end
  end

  defp run_remove(parsed) do
    host = parsed.args.host
    version = parsed.args.version

    IO.puts("Removing #{version} from #{host}...")

    case Sysd.Deploy.remove(host, version, base_opts(parsed)) do
      {:ok, :removed} -> IO.puts("Removed successfully")
      {:error, reason} -> error_exit("Remove failed: #{reason}")
    end
  end

  defp run_cleanup(parsed) do
    host = parsed.args.host

    IO.puts("Cleaning up #{host}...")

    case Sysd.Deploy.cleanup(host, base_opts(parsed)) do
      {:ok, :cleaned_up} -> IO.puts("Cleanup complete")
      {:error, reason} -> error_exit("Cleanup failed: #{reason}")
    end
  end

  defp run_setup(parsed) do
    host = parsed.args.host
    user = parsed.options[:user] || "deploy"
    opts = base_opts(parsed) ++ [user: user]

    IO.puts("Setting up #{host}...")

    case Sysd.Deploy.setup(host, opts) do
      {:ok, :setup_complete} -> IO.puts("Setup complete")
      {:error, reason} -> error_exit("Setup failed: #{reason}")
    end
  end

  defp run_systemd(parsed) do
    app = parsed.options[:app]
    user = parsed.options[:user] || "deploy"

    output = Sysd.Systemd.render(%{app: app, user: user})
    IO.write(output)
  end

  defp error_exit(msg) do
    IO.puts(:stderr, "error: #{msg}")
    System.halt(1)
  end
end
