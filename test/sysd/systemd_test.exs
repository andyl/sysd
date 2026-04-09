defmodule Sysd.SystemdTest do
  use ExUnit.Case

  alias Sysd.Systemd

  describe "render/1" do
    test "renders with required params and defaults" do
      output = Systemd.render(%{app: "myapp", user: "deploy"})

      assert output =~ "# X-Creator=sysd"
      assert output =~ "Description=myapp"
      assert output =~ "User=deploy"
      assert output =~ "WorkingDirectory=/opt/sysd/myapp/current"
      assert output =~ "ExecStart=/opt/sysd/myapp/current/bin/myapp start"
      assert output =~ "Environment=PHX_SERVER=true"
      assert output =~ "Restart=on-failure"
      assert output =~ "RestartSec=5"
      assert output =~ "[Install]"
      assert output =~ "WantedBy=multi-user.target"
    end

    test "accepts custom params" do
      output =
        Systemd.render(%{
          app: "myapp",
          user: "web",
          working_dir: "/srv/myapp",
          exec_start: "/srv/myapp/bin/start",
          environment: "MIX_ENV=prod",
          restart: "always",
          restart_sec: "10"
        })

      assert output =~ "User=web"
      assert output =~ "WorkingDirectory=/srv/myapp"
      assert output =~ "ExecStart=/srv/myapp/bin/start"
      assert output =~ "Environment=MIX_ENV=prod"
      assert output =~ "Restart=always"
      assert output =~ "RestartSec=10"
    end

    test "raises when app is missing" do
      assert_raise KeyError, fn ->
        Systemd.render(%{user: "deploy"})
      end
    end

    test "raises when user is missing" do
      assert_raise KeyError, fn ->
        Systemd.render(%{app: "myapp"})
      end
    end

    test "converts atom app name to string" do
      output = Systemd.render(%{app: :myapp, user: :deploy})
      assert output =~ "Description=myapp"
      assert output =~ "User=deploy"
    end

    test "accepts environment as a map and renders multiple Environment= lines" do
      output =
        Systemd.render(%{
          app: "myapp",
          user: "deploy",
          environment: %{"PORT" => "4001", "PHX_SERVER" => "true"}
        })

      assert output =~ "Environment=PORT=4001"
      assert output =~ "Environment=PHX_SERVER=true"
      refute output =~ "Environment=%{"
    end

    test "accepts custom description" do
      output = Systemd.render(%{app: "myapp", user: "deploy", description: "my_instance"})
      assert output =~ "Description=my_instance"
    end
  end

  describe "render_instance/3" do
    test "renders service file for an instance" do
      instance = %{name: "docpub1", env: %{"PORT" => "4001", "TITLE" => "DocPub 1"}}
      output = Systemd.render_instance("docpub", "deploy", instance)

      assert output =~ "Description=docpub1"
      assert output =~ "User=deploy"
      assert output =~ "Environment=PORT=4001"
      assert output =~ "Environment=TITLE=DocPub 1"
      assert output =~ "Environment=PHX_SERVER=true"
      assert output =~ "ExecStart=/opt/sysd/docpub/current/bin/docpub start"
    end

    test "does not duplicate PHX_SERVER if already in env" do
      instance = %{name: "inst1", env: %{"PHX_SERVER" => "false"}}
      output = Systemd.render_instance("myapp", "deploy", instance)

      assert output =~ "Environment=PHX_SERVER=false"
      refute output =~ "Environment=PHX_SERVER=true"
    end
  end
end
