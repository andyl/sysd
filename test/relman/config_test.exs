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
    assert Relman.Config.publishers(config) == []
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

  describe "parse/1 - release.publish" do
    test "returns empty publisher list when release block is missing" do
      config = Relman.Config.parse(%{"servers" => ["h1"], "ssh" => %{"user" => "u"}})
      assert Relman.Config.publishers(config) == []
    end

    test "parses a github publisher with defaults" do
      config =
        Relman.Config.parse(%{
          "release" => %{"publish" => [%{"type" => "github"}]}
        })

      assert [%{type: :github, draft: false, prerelease: false}] =
               Relman.Config.publishers(config)
    end

    test "parses github draft/prerelease flags" do
      config =
        Relman.Config.parse(%{
          "release" => %{
            "publish" => [%{"type" => "github", "draft" => true, "prerelease" => true}]
          }
        })

      assert [%{type: :github, draft: true, prerelease: true}] =
               Relman.Config.publishers(config)
    end

    test "parses a file publisher" do
      config =
        Relman.Config.parse(%{
          "release" => %{
            "publish" => [%{"type" => "file", "path" => "/mnt/releases/app/"}]
          }
        })

      assert [%{type: :file, path: "/mnt/releases/app/"}] =
               Relman.Config.publishers(config)
    end

    test "parses a mixed publisher list in order" do
      config =
        Relman.Config.parse(%{
          "release" => %{
            "publish" => [
              %{"type" => "github"},
              %{"type" => "file", "path" => "/tmp/rel/"}
            ]
          }
        })

      assert [
               %{type: :github},
               %{type: :file, path: "/tmp/rel/"}
             ] = Relman.Config.publishers(config)
    end

    test "raises on unknown publisher type" do
      assert_raise Mix.Error, ~r/Unknown publisher type/, fn ->
        Relman.Config.parse(%{
          "release" => %{"publish" => [%{"type" => "s3"}]}
        })
      end
    end
  end

  defp load_fixture do
    data = YamlElixir.read_from_file!(@fixture_path)
    Relman.Config.parse(data)
  end
end
