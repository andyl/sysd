defmodule RelDep.Deploy do
  @moduledoc """
  High-level deployment operations facade.

  All functions return `{:ok, result}` or `{:error, reason}` tuples.
  No IO, no Mix.raise, no System.halt — callers (escript CLI, Mix tasks)
  handle output and exit codes.

  Each function takes a `host` string and an `opts` keyword list.
  Required opts vary by function but typically include:

    * `:app` — application name (string)
    * `:config` — a `%RelDep.Config{}` struct (used for SSH settings)
  """

  alias RelDep.{SSH, Remote, TarballRef, Systemd}

  @doc """
  Check SSH connectivity and permissions on a host.

  Returns `{:ok, checks}` where checks is a map of results,
  or `{:error, reason}` on connection failure.
  """
  def check(host, opts) do
    with {:ok, conn} <- connect(host, opts) do
      connection =
        case SSH.run(conn, "whoami") do
          {:ok, user, 0} -> {:ok, String.trim(user)}
          _ -> {:error, "connection test failed"}
        end

      sudo =
        case SSH.run(conn, "sudo -n true") do
          {:ok, _, 0} -> :ok
          _ -> {:error, "passwordless sudo not available"}
        end

      app = Keyword.fetch!(opts, :app)
      app_path = RelDep.app_path(app)

      directory =
        case SSH.run(
               conn,
               "sudo mkdir -p #{app_path} && sudo rmdir #{app_path} 2>/dev/null; echo ok"
             ) do
          {:ok, _, 0} -> :ok
          _ -> {:error, "cannot create #{app_path}"}
        end

      {:ok, %{connection: connection, sudo: sudo, directory: directory}}
    end
  end

  @doc """
  Deploy a tarball to a host.

  The `tarball_ref` is a string parsed by `RelDep.TarballRef`. If it
  resolves to a local file, that file is uploaded and deployed.

  ## Required opts

    * `:app` — application name
    * `:version` — version string
    * `:config` — `%RelDep.Config{}` struct
  """
  def deploy(host, tarball_ref, opts) do
    app = Keyword.fetch!(opts, :app)
    version = Keyword.fetch!(opts, :version)
    dest_dir = Keyword.get(opts, :dest_dir, System.tmp_dir!())

    with {:ok, ref} <- TarballRef.parse(tarball_ref),
         {:ok, local_path} <- TarballRef.resolve(ref, dest_dir),
         {:ok, conn} <- connect(host, opts) do
      Remote.deploy(conn, app, local_path, version)

      release_info = %{
        app: app,
        version: version,
        git_sha: safe_git_sha(),
        build_host: RelDep.build_host(),
        build_timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      Remote.write_release_info(conn, app, version, release_info)
      {:ok, :deployed}
    end
  rescue
    e in RelDep.SSH.Error -> {:error, e.message}
  end

  @doc "List deployed versions on a host. Returns `{:ok, %{versions: list, current: string | nil}}`."
  def versions(host, opts) do
    app = Keyword.fetch!(opts, :app)

    with {:ok, conn} <- connect(host, opts) do
      vers = Remote.list_versions(conn, app)
      current = Remote.current_version(conn, app)
      {:ok, %{versions: vers, current: current}}
    end
  end

  @doc "Rollback to a previous version on a host."
  def rollback(host, version, opts) do
    app = Keyword.fetch!(opts, :app)

    with {:ok, conn} <- connect(host, opts) do
      Remote.rollback(conn, app, version)
      {:ok, :rolled_back}
    end
  rescue
    e in RelDep.SSH.Error -> {:error, e.message}
  end

  @doc "Get systemd service status on a host."
  def status(host, opts) do
    app = Keyword.fetch!(opts, :app)

    with {:ok, conn} <- connect(host, opts) do
      Remote.status(conn, app)
    end
  end

  @doc "Start the systemd service on a host."
  def start(host, opts) do
    app = Keyword.fetch!(opts, :app)

    with {:ok, conn} <- connect(host, opts) do
      Remote.start(conn, app)
      {:ok, :started}
    end
  rescue
    e in RelDep.SSH.Error -> {:error, e.message}
  end

  @doc "Stop the systemd service on a host."
  def stop(host, opts) do
    app = Keyword.fetch!(opts, :app)

    with {:ok, conn} <- connect(host, opts) do
      Remote.stop(conn, app)
      {:ok, :stopped}
    end
  rescue
    e in RelDep.SSH.Error -> {:error, e.message}
  end

  @doc "Restart the systemd service on a host."
  def restart(host, opts) do
    app = Keyword.fetch!(opts, :app)

    with {:ok, conn} <- connect(host, opts) do
      Remote.restart(conn, app)
      {:ok, :restarted}
    end
  rescue
    e in RelDep.SSH.Error -> {:error, e.message}
  end

  @doc "Fetch recent journal logs from a host."
  def logs(host, opts) do
    app = Keyword.fetch!(opts, :app)
    lines = Keyword.get(opts, :lines, 50)

    with {:ok, conn} <- connect(host, opts) do
      Remote.logs(conn, app, lines: lines)
    end
  end

  @doc "Tail journal logs from a host (time-bounded)."
  def tail(host, opts) do
    app = Keyword.fetch!(opts, :app)
    lines = Keyword.get(opts, :lines, 50)
    seconds = Keyword.get(opts, :seconds, 10)

    with {:ok, conn} <- connect(host, opts) do
      Remote.tail(conn, app, lines: lines, seconds: seconds)
    end
  end

  @doc "Remove a deployed version from a host."
  def remove(host, version, opts) do
    app = Keyword.fetch!(opts, :app)

    with {:ok, conn} <- connect(host, opts) do
      Remote.remove_version(conn, app, version)
      {:ok, :removed}
    end
  rescue
    e in RelDep.SSH.Error -> {:error, e.message}
  end

  @doc "Remove all RelDep files and service from a host."
  def cleanup(host, opts) do
    app = Keyword.fetch!(opts, :app)

    with {:ok, conn} <- connect(host, opts) do
      Remote.cleanup(conn, app)
      {:ok, :cleaned_up}
    end
  rescue
    e in RelDep.SSH.Error -> {:error, e.message}
  end

  @doc """
  Setup server directories and install systemd service on a host.

  ## Required opts

    * `:app` — application name
    * `:config` — `%RelDep.Config{}` struct
    * `:user` — system user for the service
  """
  def setup(host, opts) do
    app = Keyword.fetch!(opts, :app)
    user = Keyword.fetch!(opts, :user)

    with {:ok, conn} <- connect(host, opts) do
      Remote.setup_dirs(conn, app)

      service_content = Systemd.render(%{app: app, user: user})
      Remote.install_service(conn, app, service_content)

      {:ok, :setup_complete}
    end
  rescue
    e in RelDep.SSH.Error -> {:error, e.message}
  end

  # --- Private helpers ---

  defp connect(host, opts) do
    config = Keyword.get(opts, :config)
    ssh_config = if config, do: config.ssh, else: %{user: Keyword.get(opts, :user, "deploy")}
    SSH.connect(host, ssh_config)
  end

  defp safe_git_sha do
    RelDep.git_sha()
  rescue
    _ -> nil
  end
end
