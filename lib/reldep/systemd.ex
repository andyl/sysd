defmodule RelDep.Systemd do
  @moduledoc """
  Systemd service file generation for RelDep-managed applications.

  The template is embedded as a module attribute and rendered with EEx.
  All generated service files include an `# X-Creator=reldep` marker
  comment for identification.
  """

  @service_template """
  # X-Creator=reldep
  [Unit]
  Description=<%= @app %>
  After=network.target

  [Service]
  Type=simple
  User=<%= @user %>
  WorkingDirectory=<%= @working_dir %>
  Environment=<%= @environment %>
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

    * `:working_dir` — working directory (default: `/opt/reldep/<app>/current`)
    * `:exec_start` — start command (default: `/opt/reldep/<app>/current/bin/<app> start`)
    * `:environment` — environment variables (default: `PHX_SERVER=true`)
    * `:restart` — restart policy (default: `on-failure`)
    * `:restart_sec` — restart delay in seconds (default: `5`)
  """
  def render(params) when is_map(params) do
    app = Map.fetch!(params, :app) |> to_string()
    user = Map.fetch!(params, :user) |> to_string()

    assigns = %{
      app: app,
      user: user,
      working_dir: Map.get(params, :working_dir, "/opt/reldep/#{app}/current"),
      exec_start: Map.get(params, :exec_start, "/opt/reldep/#{app}/current/bin/#{app} start"),
      environment: Map.get(params, :environment, "PHX_SERVER=true"),
      restart: Map.get(params, :restart, "on-failure"),
      restart_sec: Map.get(params, :restart_sec, "5")
    }

    EEx.eval_string(@service_template, assigns: assigns)
  end
end
