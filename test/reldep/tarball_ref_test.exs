defmodule RelDep.TarballRefTest do
  use ExUnit.Case

  alias RelDep.TarballRef

  describe "parse/1" do
    test "parses file:// scheme" do
      assert {:ok, %TarballRef{scheme: :file, path: "/tmp/app.tar.gz"}} =
               TarballRef.parse("file:///tmp/app.tar.gz")
    end

    test "parses bare absolute path as file scheme" do
      assert {:ok, %TarballRef{scheme: :file, path: "/tmp/app.tar.gz"}} =
               TarballRef.parse("/tmp/app.tar.gz")
    end

    test "parses bare relative path as file scheme" do
      assert {:ok, %TarballRef{scheme: :file, path: "build/app.tar.gz"}} =
               TarballRef.parse("build/app.tar.gz")
    end

    test "parses gh:// scheme" do
      assert {:ok, %TarballRef{scheme: :github, owner: "acme", repo: "app", tag: "v1.0.0"}} =
               TarballRef.parse("gh://acme/app@v1.0.0")
    end

    test "returns error for gh:// without tag" do
      assert {:error, msg} = TarballRef.parse("gh://acme/app")
      assert msg =~ "missing @tag"
    end

    test "returns error for gh:// without owner/repo" do
      assert {:error, msg} = TarballRef.parse("gh://app@v1.0.0")
      assert msg =~ "expected gh://owner/repo@tag"
    end

    test "parses s3:// scheme" do
      assert {:ok, %TarballRef{scheme: :s3, path: "bucket/key.tar.gz"}} =
               TarballRef.parse("s3://bucket/key.tar.gz")
    end

    test "returns error for nil" do
      assert {:error, "invalid tarball reference"} = TarballRef.parse(nil)
    end

    test "returns error for empty string" do
      assert {:error, "invalid tarball reference"} = TarballRef.parse("")
    end
  end

  describe "resolve/2 - file scheme" do
    setup do
      dir =
        System.tmp_dir!() |> Path.join("tarball_ref_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "returns path when file exists", %{dir: dir} do
      path = Path.join(dir, "test.tar.gz")
      File.write!(path, "fake tarball")

      ref = %TarballRef{scheme: :file, path: path}
      assert {:ok, ^path} = TarballRef.resolve(ref, dir)
    end

    test "returns error when file doesn't exist", %{dir: dir} do
      ref = %TarballRef{scheme: :file, path: "/nonexistent/file.tar.gz"}
      assert {:error, "file not found:" <> _} = TarballRef.resolve(ref, dir)
    end
  end

  describe "resolve/2 - s3 scheme" do
    test "returns not_implemented error" do
      ref = %TarballRef{scheme: :s3, path: "bucket/key"}
      assert {:error, {:not_implemented, "s3:// scheme"}} = TarballRef.resolve(ref, "/tmp")
    end
  end
end
