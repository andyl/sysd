defmodule Relman.Publisher.FileTest do
  use ExUnit.Case, async: true

  alias Relman.Publisher.File, as: FilePub

  @app :myapp
  @version "0.1.0"
  @tar_basename "myapp-0.1.0.tar.gz"

  setup do
    tmp = System.tmp_dir!() |> Path.join("relman_file_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    dest = Path.join(tmp, "dest")
    File.mkdir_p!(dest)

    src_tar = Path.join(tmp, "src.tar.gz")
    File.write!(src_tar, "fake-tarball-bytes")

    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, tmp: tmp, dest: dest, src_tar: src_tar}
  end

  describe "preflight/1" do
    test "requires :path", _ do
      assert {:error, _} = FilePub.preflight(%{})
      assert {:error, _} = FilePub.preflight(%{path: nil})
      assert {:error, _} = FilePub.preflight(%{path: ""})
    end

    test "rejects a relative path", _ do
      assert {:error, msg} = FilePub.preflight(%{path: "relative/dir"})
      assert msg =~ "absolute"
    end

    test "rejects a non-existent directory", %{tmp: tmp} do
      missing = Path.join(tmp, "nope")
      assert {:error, msg} = FilePub.preflight(%{path: missing})
      assert msg =~ "does not exist"
    end

    test "accepts a writable, absolute directory", %{dest: dest} do
      assert :ok = FilePub.preflight(%{path: dest})
    end
  end

  describe "publish/4" do
    test "copies the tarball to <path>/<app>-<version>.tar.gz", ctx do
      assert {:ok, url} =
               FilePub.publish(%{path: ctx.dest}, ctx.src_tar, @app, @version)

      target = Path.join(ctx.dest, @tar_basename)
      assert File.exists?(target)
      assert File.read!(target) == "fake-tarball-bytes"
      assert url =~ target
    end

    test "errors if artifact already exists without :replace", ctx do
      target = Path.join(ctx.dest, @tar_basename)
      File.write!(target, "old")

      assert {:error, msg} = FilePub.publish(%{path: ctx.dest}, ctx.src_tar, @app, @version)
      assert msg =~ "already exists"
      assert File.read!(target) == "old"
    end

    test "overwrites when :replace is set", ctx do
      target = Path.join(ctx.dest, @tar_basename)
      File.write!(target, "old")

      assert {:ok, _} =
               FilePub.publish(
                 %{path: ctx.dest, replace: true},
                 ctx.src_tar,
                 @app,
                 @version
               )

      assert File.read!(target) == "fake-tarball-bytes"
    end
  end

  describe "fetch/4" do
    test "copies the file back into dest_dir", ctx do
      # Seed the "published" tarball.
      FilePub.publish(%{path: ctx.dest}, ctx.src_tar, @app, @version)

      fetch_dir = Path.join(ctx.tmp, "build")

      assert {:ok, _} =
               FilePub.fetch(%{path: ctx.dest}, @app, @version, fetch_dir)

      assert File.exists?(Path.join(fetch_dir, @tar_basename))
    end

    test "errors when the artifact is missing", ctx do
      assert {:error, _} =
               FilePub.fetch(%{path: ctx.dest}, @app, @version, Path.join(ctx.tmp, "nope"))
    end
  end
end
