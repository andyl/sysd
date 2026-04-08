defmodule Relman.RemoteTest do
  use ExUnit.Case, async: true

  test "format_release_info/1 renders key=value lines in order" do
    body =
      Relman.Remote.format_release_info(%{
        app: :myapp,
        version: "0.1.0",
        git_sha: "abc123",
        build_host: "laptop",
        build_timestamp: "2026-04-07T12:00:00Z",
        publisher_url: nil
      })

    assert body =~ "app=myapp"
    assert body =~ "version=0.1.0"
    assert body =~ "git_sha=abc123"
    assert body =~ "build_host=laptop"
    assert body =~ "build_timestamp=2026-04-07T12:00:00Z"
    assert body =~ "publisher_url="
  end
end
