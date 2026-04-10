defmodule Sysd.ConfigTest do
  use ExUnit.Case

  @fixture_dir "test/fixtures"
  @fixture_path "#{@fixture_dir}/sysd.yaml"

  setup do
    File.mkdir_p!(@fixture_dir)

    on_exit(fn ->
      File.rm_rf!(@fixture_dir)
      System.delete_env("SYSD_CONFIG_FILE")
    end)

    :ok
  end

  test "load/0 raises when config file is missing" do
    assert_raise Mix.Error, ~r/Config file not found/, fn ->
      Sysd.Config.load()
    end
  end

  test "load/0 parses a valid YAML config" do
    yaml = """
    servers:
      - host1
      - host2
    ssh:
      user: deploy
    """

    File.write!(@fixture_path, yaml)

    config = load_fixture()

    assert config.servers == ["host1", "host2"]
    assert config.ssh[:user] == "deploy"
  end

  test "write/1 writes config back to YAML" do
    path = @fixture_path
    File.mkdir_p!(Path.dirname(path))

    yaml = """
    servers:
      - server1
    ssh:
      user: admin
    """

    File.write!(path, yaml)

    parsed = load_fixture()
    assert parsed.servers == ["server1"]
    assert parsed.ssh[:user] == "admin"
  end

  test "remove_server/2 removes a server from config" do
    config = %Sysd.Config{servers: ["host1", "host2"], ssh: %{user: "deploy"}}
    updated = %{config | servers: Enum.reject(config.servers, &(&1 == "host1"))}

    assert updated.servers == ["host2"]
  end

  describe "load/1 - precedence chain" do
    test "loads from explicit config_path" do
      path = Path.join(@fixture_dir, "explicit.yml")

      File.write!(path, """
      servers:
        - explicit-host
      ssh:
        user: admin
      """)

      assert {:ok, config} = Sysd.Config.load(config_path: path)
      assert config.servers == ["explicit-host"]
    end

    test "returns error when explicit path doesn't exist" do
      assert {:error, "config file not found:" <> _} =
               Sysd.Config.load(config_path: "/nonexistent/config.yml")
    end

    test "loads from SYSD_CONFIG_FILE env var" do
      path = Path.join(@fixture_dir, "env.yml")

      File.write!(path, """
      servers:
        - env-host
      ssh:
        user: envuser
      """)

      System.put_env("SYSD_CONFIG_FILE", path)

      assert {:ok, config} = Sysd.Config.load([])
      assert config.servers == ["env-host"]
    end

    test "explicit path takes priority over SYSD_CONFIG_FILE" do
      env_path = Path.join(@fixture_dir, "env.yml")
      explicit_path = Path.join(@fixture_dir, "explicit.yml")

      File.write!(env_path, """
      servers:
        - env-host
      ssh:
        user: envuser
      """)

      File.write!(explicit_path, """
      servers:
        - explicit-host
      ssh:
        user: admin
      """)

      System.put_env("SYSD_CONFIG_FILE", env_path)

      assert {:ok, config} = Sysd.Config.load(config_path: explicit_path)
      assert config.servers == ["explicit-host"]
    end

    test "parses multi-app config with :app option" do
      path = Path.join(@fixture_dir, "multi.yml")

      File.write!(path, """
      apps:
        myapp:
          servers:
            - app-host
          ssh:
            user: appuser
      """)

      assert {:ok, config} = Sysd.Config.load(config_path: path, app: "myapp")
      assert config.servers == ["app-host"]
      assert config.ssh[:user] == "appuser"
      assert config.app == "myapp"
    end
  end

  describe "parse/1 - instances" do
    test "parses servers with instances" do
      data = %{
        "servers" => [
          %{
            "host" => "host1",
            "instances" => [
              %{
                "instance_name" => "app1",
                "environment_variables" => %{"PORT" => 4001, "TITLE" => "App One"}
              },
              %{
                "instance_name" => "app2",
                "environment_variables" => %{"PORT" => 4002}
              }
            ]
          }
        ],
        "ssh" => %{"user" => "deploy"}
      }

      config = Sysd.Config.parse(data)
      assert config.servers == ["host1"]
      assert map_size(config.instances) == 1

      [inst1, inst2] = config.instances["host1"]
      assert inst1.name == "app1"
      assert inst1.env == %{"PORT" => "4001", "TITLE" => "App One"}
      assert inst2.name == "app2"
      assert inst2.env == %{"PORT" => "4002"}
    end

    test "parses mixed legacy and instance servers" do
      data = %{
        "servers" => [
          "legacy-host",
          %{
            "host" => "instance-host",
            "instances" => [
              %{"instance_name" => "inst1", "environment_variables" => %{"PORT" => 4001}}
            ]
          }
        ],
        "ssh" => %{"user" => "deploy"}
      }

      config = Sysd.Config.parse(data)
      assert config.servers == ["legacy-host", "instance-host"]
      assert config.instances["legacy-host"] == nil
      assert length(config.instances["instance-host"]) == 1
    end

    test "server map without instances gets empty instance list" do
      data = %{
        "servers" => [%{"host" => "host1"}],
        "ssh" => %{"user" => "deploy"}
      }

      config = Sysd.Config.parse(data)
      assert config.servers == ["host1"]
      assert config.instances == %{}
    end
  end

  describe "instances_for_host/2" do
    test "returns instances for a host with instances" do
      config = %Sysd.Config{
        servers: ["host1"],
        instances: %{"host1" => [%{name: "inst1", env: %{"PORT" => "4001"}}]}
      }

      assert [%{name: "inst1"}] = Sysd.Config.instances_for_host(config, "host1")
    end

    test "returns empty list for a legacy host" do
      config = %Sysd.Config{servers: ["host1"], instances: %{}}
      assert Sysd.Config.instances_for_host(config, "host1") == []
    end
  end

  describe "service_names/3" do
    test "returns instance service names for a host with instances" do
      config = %Sysd.Config{
        servers: ["host1"],
        instances: %{
          "host1" => [
            %{name: "docpub1", env: %{}},
            %{name: "docpub2", env: %{}}
          ]
        }
      }

      assert Sysd.Config.service_names(config, "host1", "docpub") == [
               "sysd_docpub1",
               "sysd_docpub2"
             ]
    end

    test "returns app name for a legacy host" do
      config = %Sysd.Config{servers: ["host1"], instances: %{}}
      assert Sysd.Config.service_names(config, "host1", "myapp") == ["sysd_myapp"]
    end
  end

  describe "load/1 - instances from YAML" do
    test "loads config with instances from file" do
      path = Path.join(@fixture_dir, "instances.yml")

      File.write!(path, """
      servers:
        - host: web1
          instances:
            - instance_name: app_a
              environment_variables:
                PORT: 4001
                DATA_DIR: /data/a
            - instance_name: app_b
              environment_variables:
                PORT: 4002
      ssh:
        user: deploy
      """)

      assert {:ok, config} = Sysd.Config.load(config_path: path)
      assert config.servers == ["web1"]
      assert [inst_a, inst_b] = config.instances["web1"]
      assert inst_a.name == "app_a"
      assert inst_a.env["PORT"] == "4001"
      assert inst_a.env["DATA_DIR"] == "/data/a"
      assert inst_b.name == "app_b"
    end
  end

  defp load_fixture do
    data = YamlElixir.read_from_file!(@fixture_path)
    Sysd.Config.parse(data)
  end
end
