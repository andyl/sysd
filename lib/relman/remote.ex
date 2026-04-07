defmodule Relman.Remote do
  @moduledoc """
  High-level operations on a remote server over an SSH connection.

  Each function takes an open SSH connection (as returned by
  `Relman.SSH.connect/2`) and performs one or more commands on the
  remote host. These are the building blocks used by the Mix tasks.
  """

  alias Relman.SSH

  @doc "Create the `/opt/relman/<appname>/{archives,releases}` directory structure."
  def setup_dirs(conn, app_name) do
    SSH.run!(conn, "sudo mkdir -p #{Relman.archives_path(app_name)}")
    SSH.run!(conn, "sudo mkdir -p #{Relman.releases_path(app_name)}")
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
    remote_archive = "#{Relman.archives_path(app_name)}/#{version}.tar.gz"
    remote_release = "#{Relman.releases_path(app_name)}/#{version}"

    tmp_archive = "/tmp/#{app_name}-#{version}.tar.gz"
    SSH.upload(conn, local_tar_path, tmp_archive)
    SSH.run!(conn, "sudo mv #{tmp_archive} #{remote_archive}")

    SSH.run!(conn, "sudo mkdir -p #{remote_release}")
    SSH.run!(conn, "sudo tar -xzf #{remote_archive} -C #{remote_release}")
    SSH.run!(conn, "sudo ln -sfn #{remote_release} #{Relman.current_path(app_name)}")

    case SSH.run(conn, "sudo systemctl is-active #{app_name}") do
      {:ok, _, 0} ->
        SSH.run!(conn, "sudo systemctl restart #{app_name}")

      _ ->
        SSH.run!(conn, "sudo systemctl start #{app_name}")
    end
  end

  @doc "List all release versions present on the remote server."
  def list_versions(conn, app_name) do
    case SSH.run(conn, "ls #{Relman.releases_path(app_name)}") do
      {:ok, output, 0} ->
        output |> String.trim() |> String.split("\n", trim: true)

      _ ->
        []
    end
  end

  @doc "Return the currently active version by reading the `current` symlink, or `nil`."
  def current_version(conn, app_name) do
    case SSH.run(conn, "readlink #{Relman.current_path(app_name)}") do
      {:ok, output, 0} -> output |> String.trim() |> Path.basename()
      _ -> nil
    end
  end

  @doc "Switch the `current` symlink to the given version and restart the service."
  def rollback(conn, app_name, version) do
    remote_release = "#{Relman.releases_path(app_name)}/#{version}"
    SSH.run!(conn, "sudo ln -sfn #{remote_release} #{Relman.current_path(app_name)}")
    SSH.run!(conn, "sudo systemctl restart #{app_name}")
  end

  @doc "Delete a release version and its archive. Refuses to remove the current version."
  def remove_version(conn, app_name, version) do
    current = current_version(conn, app_name)

    if current == version do
      Mix.raise("Cannot remove the currently active version: #{version}")
    end

    SSH.run!(conn, "sudo rm -rf #{Relman.releases_path(app_name)}/#{version}")
    SSH.run!(conn, "sudo rm -f #{Relman.archives_path(app_name)}/#{version}.tar.gz")
  end

  @doc "Stop the service, remove the service file, and delete all Relman files from the server."
  def cleanup(conn, app_name) do
    SSH.run(conn, "sudo systemctl stop #{app_name}")
    SSH.run(conn, "sudo systemctl disable #{app_name}")
    SSH.run(conn, "sudo rm -f /etc/systemd/system/#{app_name}.service")
    SSH.run(conn, "sudo systemctl daemon-reload")
    SSH.run!(conn, "sudo rm -rf #{Relman.app_path(app_name)}")
  end
end
