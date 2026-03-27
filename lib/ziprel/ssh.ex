defmodule Ziprel.SSH do
  @moduledoc """
  SSH connectivity layer wrapping SSHEx and Erlang's `:ssh_sftp`.

  Provides command execution and file upload over SSH. Connections
  use the system SSH agent for authentication.
  """

  @doc """
  Open an SSH connection to `host` using the given SSH config.

  The `ssh_config` map must include a `:user` key. Authentication
  is handled by the system SSH agent.

  Returns `{:ok, conn}` or `{:error, reason}`.
  """
  def connect(host, ssh_config) do
    :ssh.start()

    opts = [
      ip: to_charlist(host),
      user: to_charlist(ssh_config[:user])
    ]

    SSHEx.connect(opts)
  end

  @doc """
  Execute a command on the remote server.

  Returns `{:ok, output, exit_status}` or `{:error, reason}`.
  """
  def run(conn, cmd) do
    SSHEx.run(conn, to_charlist(cmd))
  end

  @doc """
  Execute a command on the remote server, raising on failure.

  Returns the stdout string on success (exit status 0).
  Raises a `Mix.Error` on non-zero exit or connection error.
  """
  def run!(conn, cmd) do
    case run(conn, cmd) do
      {:ok, output, 0} ->
        output

      {:ok, output, status} ->
        Mix.raise("Command failed (exit #{status}): #{cmd}\n#{output}")

      {:error, reason} ->
        Mix.raise("SSH error: #{inspect(reason)}")
    end
  end

  @doc """
  Upload a local file to the remote server via SFTP.

  Opens an SFTP channel on the existing SSH connection, writes the
  file contents, and closes the channel. Raises on failure.
  """
  def upload(conn, local_path, remote_path) do
    {:ok, channel} = :ssh_sftp.start_channel(conn)
    content = File.read!(local_path)

    case :ssh_sftp.write_file(channel, to_charlist(remote_path), content) do
      :ok ->
        IO.puts("Upload successful")
        :ssh_sftp.stop_channel(channel)
        :ok

      {:error, reason} ->
        :ssh_sftp.stop_channel(channel)
        Mix.raise("SFTP upload failed: #{inspect(reason)}")
    end
  end
end
