defmodule Sysd.ConfigTest do
  use ExUnit.Case

  @fixture_dir "test/fixtures"
  @fixture_path "#{@fixture_dir}/sysd.yaml"

  setup do
    File.mkdir_p!(@fixture_dir)

    on_exit(fn ->
      File.rm_rf!(@fixture_dir)
      System.delete_env("RELDEP_CONFIG")
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

    test "loads from RELDEP_CONFIG env var" do
      path = Path.join(@fixture_dir, "env.yml")

      File.write!(path, """
      servers:
        - env-host
      ssh:
        user: envuser
      """)

      System.put_env("RELDEP_CONFIG", path)

      assert {:ok, config} = Sysd.Config.load([])
      assert config.servers == ["env-host"]
    end

    test "explicit path takes priority over RELDEP_CONFIG" do
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

      System.put_env("RELDEP_CONFIG", env_path)

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

  defp load_fixture do
    data = YamlElixir.read_from_file!(@fixture_path)
    Sysd.Config.parse(data)
  end
end
