defmodule Sysd.Deploy do
  @moduledoc """
  High-level deployment operations facade.

  All functions return `{:ok, result}` or `{:error, reason}` tuples.
  No IO, no Mix.raise, no System.halt — callers (escript CLI, Mix tasks)
  handle output and exit codes.

  Each function takes a `host` string and an `opts` keyword list.
  Required opts vary by function but typically include:

    * `:app` — application name (string)
    * `:config` — a `%Sysd.Config{}` struct (used for SSH settings)
  """

  alias Sysd.{SSH, Remote, TarballRef, Systemd}

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
      app_path = Sysd.app_path(app)

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

  The `tarball_ref` is a string parsed by `Sysd.TarballRef`. If it
  resolves to a local file, that file is uploaded and deployed.

  When the host has instances configured, the release is uploaded once
  and each instance service is restarted. When `:instance` is given,
  only that instance is restarted.

  ## Required opts

    * `:app` — application name
    * `:version` — version string
    * `:config` — `%Sysd.Config{}` struct
  """
  def deploy(host, tarball_ref, opts) do
    app = Keyword.fetch!(opts, :app)
    version = Keyword.fetch!(opts, :version)
    config = Keyword.get(opts, :config)
    dest_dir = Keyword.get(opts, :dest_dir, System.tmp_dir!())

    with {:ok, ref} <- TarballRef.parse(tarball_ref),
         {:ok, local_path} <- TarballRef.resolve(ref, dest_dir),
         {:ok, conn} <- connect(host, opts) do
      service_names = target_service_names(config, host, app, opts)
      Remote.deploy_release(conn, app, local_path, version)

      Enum.each(service_names, fn svc ->
        Remote.restart_or_start(conn, svc)
      end)

      release_info = %{
        app: app,
        version: version,
        git_sha: safe_git_sha(),
        build_host: Sysd.build_host(),
        build_timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      Remote.write_release_info(conn, app, version, release_info)
      {:ok, :deployed}
    end
  rescue
    e in Sysd.SSH.Error -> {:error, e.message}
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

  @doc "Rollback to a previous version on a host. Restarts all instances unless `:instance` is given."
  def rollback(host, version, opts) do
    app = Keyword.fetch!(opts, :app)
    config = Keyword.get(opts, :config)

    with {:ok, conn} <- connect(host, opts) do
      service_names = target_service_names(config, host, app, opts)
      remote_release = "#{Sysd.releases_path(app)}/#{version}"
      SSH.run!(conn, "sudo ln -sfn #{remote_release} #{Sysd.current_path(app)}")

      Enum.each(service_names, fn svc ->
        SSH.run!(conn, "sudo systemctl restart #{svc}")
      end)

      {:ok, :rolled_back}
    end
  rescue
    e in Sysd.SSH.Error -> {:error, e.message}
  end

  @doc """
  Get systemd service status on a host.

  With instances configured, returns `{:ok, %{service_name => status}}`.
  With `:instance` option or legacy mode, returns `{:ok, status}`.
  """
  def status(host, opts) do
    app = Keyword.fetch!(opts, :app)
    config = Keyword.get(opts, :config)

    with {:ok, conn} <- connect(host, opts) do
      service_names = target_service_names(config, host, app, opts)

      case service_names do
        [single] ->
          Remote.status(conn, single)

        multiple ->
          results =
            Map.new(multiple, fn svc ->
              {:ok, s} = Remote.status(conn, svc)
              {svc, s}
            end)

          {:ok, results}
      end
    end
  end

  @doc "Start the systemd service on a host. Operates on all instances unless `:instance` is given."
  def start(host, opts) do
    app = Keyword.fetch!(opts, :app)
    config = Keyword.get(opts, :config)

    with {:ok, conn} <- connect(host, opts) do
      Enum.each(target_service_names(config, host, app, opts), fn svc ->
        Remote.start(conn, svc)
      end)

      {:ok, :started}
    end
  rescue
    e in Sysd.SSH.Error -> {:error, e.message}
  end

  @doc "Stop the systemd service on a host. Operates on all instances unless `:instance` is given."
  def stop(host, opts) do
    app = Keyword.fetch!(opts, :app)
    config = Keyword.get(opts, :config)

    with {:ok, conn} <- connect(host, opts) do
      Enum.each(target_service_names(config, host, app, opts), fn svc ->
        Remote.stop(conn, svc)
      end)

      {:ok, :stopped}
    end
  rescue
    e in Sysd.SSH.Error -> {:error, e.message}
  end

  @doc "Restart the systemd service on a host. Operates on all instances unless `:instance` is given."
  def restart(host, opts) do
    app = Keyword.fetch!(opts, :app)
    config = Keyword.get(opts, :config)

    with {:ok, conn} <- connect(host, opts) do
      Enum.each(target_service_names(config, host, app, opts), fn svc ->
        Remote.restart(conn, svc)
      end)

      {:ok, :restarted}
    end
  rescue
    e in Sysd.SSH.Error -> {:error, e.message}
  end

  @doc "Fetch recent journal logs from a host. Operates on all instances unless `:instance` is given."
  def logs(host, opts) do
    app = Keyword.fetch!(opts, :app)
    config = Keyword.get(opts, :config)
    lines = Keyword.get(opts, :lines, 50)

    with {:ok, conn} <- connect(host, opts) do
      service_names = target_service_names(config, host, app, opts)

      case service_names do
        [single] ->
          Remote.logs(conn, single, lines: lines)

        multiple ->
          results =
            Map.new(multiple, fn svc ->
              {:ok, output} = Remote.logs(conn, svc, lines: lines)
              {svc, output}
            end)

          {:ok, results}
      end
    end
  end

  @doc "Tail journal logs from a host (time-bounded). Operates on all instances unless `:instance` is given."
  def tail(host, opts) do
    app = Keyword.fetch!(opts, :app)
    config = Keyword.get(opts, :config)
    lines = Keyword.get(opts, :lines, 50)
    seconds = Keyword.get(opts, :seconds, 10)

    with {:ok, conn} <- connect(host, opts) do
      service_names = target_service_names(config, host, app, opts)

      case service_names do
        [single] ->
          Remote.tail(conn, single, lines: lines, seconds: seconds)

        multiple ->
          results =
            Map.new(multiple, fn svc ->
              {:ok, output} = Remote.tail(conn, svc, lines: lines, seconds: seconds)
              {svc, output}
            end)

          {:ok, results}
      end
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
    e in Sysd.SSH.Error -> {:error, e.message}
  end

  @doc """
  Remove all Sysd files and service from a host.

  When the host has instances, stops and removes all instance services
  before deleting app files. When `:instance` is given, only that
  instance service is removed (app files are kept).
  """
  def cleanup(host, opts) do
    app = Keyword.fetch!(opts, :app)
    config = Keyword.get(opts, :config)
    instance = Keyword.get(opts, :instance)

    with {:ok, conn} <- connect(host, opts) do
      instances = if config, do: Sysd.Config.instances_for_host(config, host), else: []

      cond do
        instance != nil ->
          Remote.cleanup_instance(conn, "sysd_#{instance}")
          {:ok, :cleaned_up}

        instances != [] ->
          Remote.cleanup_all_instances(conn, app)
          {:ok, :cleaned_up}

        true ->
          Remote.cleanup(conn, app)
          {:ok, :cleaned_up}
      end
    end
  rescue
    e in Sysd.SSH.Error -> {:error, e.message}
  end

  @doc """
  Setup server directories and install systemd service on a host.

  When the host has instances configured, installs a separate service
  file for each instance (`sysd_<instance_name>.service`).

  ## Required opts

    * `:app` — application name
    * `:config` — `%Sysd.Config{}` struct
    * `:user` — system user for the service
  """
  def setup(host, opts) do
    app = Keyword.fetch!(opts, :app)
    user = Keyword.fetch!(opts, :user)
    config = Keyword.get(opts, :config)

    with {:ok, conn} <- connect(host, opts) do
      Remote.setup_dirs(conn, app)

      instances = if config, do: Sysd.Config.instances_for_host(config, host), else: []

      if instances == [] do
        service_name = "sysd_#{app}"
        service_content = Systemd.render(%{app: app, user: user})
        Remote.install_service(conn, service_name, service_content)
      else
        Enum.each(instances, fn instance ->
          service_name = "sysd_#{instance.name}"
          service_content = Systemd.render_instance(app, user, instance)
          Remote.install_service(conn, service_name, service_content)
        end)
      end

      {:ok, :setup_complete}
    end
  rescue
    e in Sysd.SSH.Error -> {:error, e.message}
  end

  # --- Private helpers ---

  defp target_service_names(config, host, app, opts) do
    instance = Keyword.get(opts, :instance)

    cond do
      instance != nil ->
        ["sysd_#{instance}"]

      config != nil ->
        Sysd.Config.service_names(config, host, app)

      true ->
        ["sysd_#{app}"]
    end
  end

  defp connect(host, opts) do
    config = Keyword.get(opts, :config)
    ssh_config = if config, do: config.ssh, else: %{user: Keyword.get(opts, :user, "deploy")}
    SSH.connect(host, ssh_config)
  end

  defp safe_git_sha do
    Sysd.git_sha()
  rescue
    _ -> nil
  end
end
