defmodule Relman.ConfigTest do
  use ExUnit.Case

  @fixture_dir "test/fixtures"
  @fixture_path "#{@fixture_dir}/relman.yaml"

  setup do
    File.mkdir_p!(@fixture_dir)

    on_exit(fn ->
      File.rm_rf!(@fixture_dir)
    end)

    :ok
  end

  test "load/0 raises when config file is missing" do
    assert_raise Mix.Error, ~r/Config file not found/, fn ->
      Relman.Config.load()
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
    config = %Relman.Config{servers: ["host1", "host2"], ssh: %{user: "deploy"}}
    updated = %{config | servers: Enum.reject(config.servers, &(&1 == "host1"))}

    assert updated.servers == ["host2"]
  end

  defp load_fixture do
    data = YamlElixir.read_from_file!(@fixture_path)

    %Relman.Config{
      servers: data["servers"] || [],
      ssh: Map.new(data["ssh"] || %{}, fn {k, v} -> {String.to_atom(k), v} end)
    }
  end
end
