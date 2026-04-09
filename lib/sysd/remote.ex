defmodule Sysd.Remote do
  @moduledoc """
  High-level operations on a remote server over an SSH connection.

  Each function takes an open SSH connection (as returned by
  `Sysd.SSH.connect/2`) and performs one or more commands on the
  remote host. These are the building blocks used by the Mix tasks.
  """

  alias Sysd.SSH

  @doc "Create the `/opt/sysd/<appname>/{archives,releases}` directory structure."
  def setup_dirs(conn, app_name) do
    SSH.run!(conn, "sudo mkdir -p #{Sysd.archives_path(app_name)}")
    SSH.run!(conn, "sudo mkdir -p #{Sysd.releases_path(app_name)}")
  end

  @doc "Write a systemd service file, reload systemd, and enable the service."
  def install_service(conn, app_name, service_content) do
    tmp_path = "/tmp/#{app_name}.service"
    service_path = "/etc/systemd/system/#{app_name}.service"

    SSH.run!(conn, "cat > #{tmp_path} << 'SERVICEEOF'\n#{service_content}\nSERVICEEOF")
    SSH.run!(conn, "sudo mv #{tmp_path} #{service_path}")
    SSH.run!(conn, "sudo systemctl daemon-reload")
    SSH.run!(conn, "sudo systemctl enable #{app_name}")
  end

  @doc "Upload a release tarball, extract it, update the symlink, and start/restart the service."
  def deploy(conn, app_name, local_tar_path, version) do
    remote_archive = "#{Sysd.archives_path(app_name)}/#{version}.tar.gz"
    remote_release = "#{Sysd.releases_path(app_name)}/#{version}"

    tmp_archive = "/tmp/#{app_name}-#{version}.tar.gz"
    SSH.upload(conn, local_tar_path, tmp_archive)
    SSH.run!(conn, "sudo mv #{tmp_archive} #{remote_archive}")

    SSH.run!(conn, "sudo mkdir -p #{remote_release}")
    SSH.run!(conn, "sudo tar -xzf #{remote_archive} -C #{remote_release}")
    SSH.run!(conn, "sudo ln -sfn #{remote_release} #{Sysd.current_path(app_name)}")

    case SSH.run(conn, "sudo systemctl is-active #{app_name}") do
      {:ok, _, 0} ->
        SSH.run!(conn, "sudo systemctl restart #{app_name}")

      _ ->
        SSH.run!(conn, "sudo systemctl start #{app_name}")
    end
  end

  @doc """
  Write a `RELEASE_INFO` file into the remote release directory for
  an app/version. The file is a simple `key=value` text document used
  for incident debugging — expected keys include `git_sha`,
  `build_host`, `build_timestamp`, and optionally `publisher_url`.
  """
  def write_release_info(conn, app_name, version, info) when is_map(info) do
    body = format_release_info(info)
    release_dir = "#{Sysd.releases_path(app_name)}/#{version}"
    remote_path = "#{release_dir}/RELEASE_INFO"
    tmp_path = "/tmp/#{app_name}-#{version}-RELEASE_INFO"

    SSH.run!(conn, "cat > #{tmp_path} << 'RELINFOEOF'\n#{body}\nRELINFOEOF")
    SSH.run!(conn, "sudo mv #{tmp_path} #{remote_path}")
    :ok
  end

  @doc false
  def format_release_info(info) do
    info
    |> Enum.map(fn {k, v} -> "#{k}=#{format_value(v)}" end)
    |> Enum.join("\n")
  end

  defp format_value(nil), do: ""
  defp format_value(v) when is_binary(v), do: v
  defp format_value(v), do: to_string(v)

  @doc "List all release versions present on the remote server."
  def list_versions(conn, app_name) do
    case SSH.run(conn, "ls #{Sysd.releases_path(app_name)}") do
      {:ok, output, 0} ->
        output |> String.trim() |> String.split("\n", trim: true)

      _ ->
        []
    end
  end

  @doc "Return the currently active version by reading the `current` symlink, or `nil`."
  def current_version(conn, app_name) do
    case SSH.run(conn, "readlink #{Sysd.current_path(app_name)}") do
      {:ok, output, 0} -> output |> String.trim() |> Path.basename()
      _ -> nil
    end
  end

  @doc "Switch the `current` symlink to the given version and restart the service."
  def rollback(conn, app_name, version) do
    remote_release = "#{Sysd.releases_path(app_name)}/#{version}"
    SSH.run!(conn, "sudo ln -sfn #{remote_release} #{Sysd.current_path(app_name)}")
    SSH.run!(conn, "sudo systemctl restart #{app_name}")
  end

  @doc "Delete a release version and its archive. Refuses to remove the current version."
  def remove_version(conn, app_name, version) do
    current = current_version(conn, app_name)

    if current == version do
      raise Sysd.SSH.Error, "Cannot remove the currently active version: #{version}"
    end

    SSH.run!(conn, "sudo rm -rf #{Sysd.releases_path(app_name)}/#{version}")
    SSH.run!(conn, "sudo rm -f #{Sysd.archives_path(app_name)}/#{version}.tar.gz")
  end

  @doc "Check if the systemd service is active. Returns `{:ok, status_string}` or `{:error, reason}`."
  def status(conn, app_name) do
    case SSH.run(conn, "sudo systemctl is-active #{app_name}") do
      {:ok, output, 0} -> {:ok, String.trim(output)}
      {:ok, output, _} -> {:ok, String.trim(output)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Start the systemd service."
  def start(conn, app_name) do
    SSH.run!(conn, "sudo systemctl start #{app_name}")
    :ok
  end

  @doc "Stop the systemd service."
  def stop(conn, app_name) do
    SSH.run!(conn, "sudo systemctl stop #{app_name}")
    :ok
  end

  @doc "Restart the systemd service."
  def restart(conn, app_name) do
    SSH.run!(conn, "sudo systemctl restart #{app_name}")
    :ok
  end

  @doc "Fetch recent journal logs for the service. Returns `{:ok, log_output}`."
  def logs(conn, app_name, opts \\ []) do
    lines = Keyword.get(opts, :lines, 50)

    case SSH.run(conn, "sudo journalctl -u #{app_name} -n #{lines} --no-pager") do
      {:ok, output, 0} -> {:ok, output}
      {:ok, output, _} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Tail journal logs for the service (time-bounded). Returns `{:ok, log_output}`."
  def tail(conn, app_name, opts \\ []) do
    lines = Keyword.get(opts, :lines, 50)
    seconds = Keyword.get(opts, :seconds, 10)

    cmd =
      "timeout #{seconds} sudo journalctl -u #{app_name} -f -n #{lines} --no-pager 2>/dev/null; true"

    case SSH.run(conn, cmd) do
      {:ok, output, _} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stop the service, remove the service file, and delete all Sysd files from the server."
  def cleanup(conn, app_name) do
    SSH.run(conn, "sudo systemctl stop #{app_name}")
    SSH.run(conn, "sudo systemctl disable #{app_name}")
    SSH.run(conn, "sudo rm -f /etc/systemd/system/#{app_name}.service")
    SSH.run(conn, "sudo systemctl daemon-reload")
    SSH.run!(conn, "sudo rm -rf #{Sysd.app_path(app_name)}")
  end
end
