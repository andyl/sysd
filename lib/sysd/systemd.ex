defmodule Sysd.Systemd do
  @moduledoc """
  Systemd service file generation for Sysd-managed applications.

  The template is embedded as a module attribute and rendered with EEx.
  All generated service files include an `# X-Creator=sysd` marker
  comment for identification.
  """

  @service_template """
  # X-Creator=sysd
  [Unit]
  Description=<%= @description %>
  After=network.target

  [Service]
  Type=simple
  User=<%= @user %>
  WorkingDirectory=<%= @working_dir %>
  <%= @environment_lines %>
  ExecStart=<%= @exec_start %>
  Restart=<%= @restart %>
  RestartSec=<%= @restart_sec %>

  [Install]
  WantedBy=multi-user.target
  """

  @doc """
  Render a systemd service file from the embedded template.

  ## Required params

    * `:app` — application name
    * `:user` — system user to run as

  ## Optional params

    * `:description` — unit description (default: app name)
    * `:working_dir` — working directory (default: `/opt/sysd/<app>/current`)
    * `:exec_start` — start command (default: `/opt/sysd/<app>/current/bin/<app> start`)
    * `:environment` — environment variables as a string or map (default: `"PHX_SERVER=true"`)
    * `:restart` — restart policy (default: `on-failure`)
    * `:restart_sec` — restart delay in seconds (default: `5`)
  """
  def render(params) when is_map(params) do
    app = Map.fetch!(params, :app) |> to_string()
    user = Map.fetch!(params, :user) |> to_string()

    environment_lines = format_environment(Map.get(params, :environment, "PHX_SERVER=true"))

    assigns = %{
      description: Map.get(params, :description, app),
      user: user,
      working_dir: Map.get(params, :working_dir, "/opt/sysd/#{app}/current"),
      exec_start: Map.get(params, :exec_start, "/opt/sysd/#{app}/current/bin/#{app} start"),
      environment_lines: environment_lines,
      restart: Map.get(params, :restart, "on-failure"),
      restart_sec: Map.get(params, :restart_sec, "5")
    }

    EEx.eval_string(@service_template, assigns: assigns)
  end

  @doc """
  Render a systemd service file for a named instance.

  Builds params from the instance config and delegates to `render/1`.
  The instance name is used as the Description and the environment
  variables map is merged with the default `PHX_SERVER=true`.
  """
  def render_instance(app, user, %{name: name, env: env}) do
    merged_env = Map.put_new(env, "PHX_SERVER", "true")

    render(%{
      app: app,
      user: user,
      description: name,
      environment: merged_env
    })
  end

  defp format_environment(env) when is_binary(env) do
    "Environment=#{env}"
  end

  defp format_environment(env) when is_map(env) do
    env
    |> Enum.map(fn {k, v} -> "Environment=#{k}=#{v}" end)
    |> Enum.join("\n")
  end
end
