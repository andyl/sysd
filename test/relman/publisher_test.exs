defmodule Relman.PublisherTest do
  use ExUnit.Case, async: true

  defmodule StubOk do
    @behaviour Relman.Publisher
    def preflight(_spec), do: :ok
    def publish(_spec, _tar, _app, _ver), do: {:ok, "stub://ok"}
    def fetch(_spec, _app, _ver, _dest), do: {:ok, "stub://fetched"}
  end

  defmodule StubFail do
    @behaviour Relman.Publisher
    def preflight(_spec), do: {:error, "nope"}
    def publish(_spec, _tar, _app, _ver), do: {:error, "publish boom"}
    def fetch(_spec, _app, _ver, _dest), do: {:error, "fetch boom"}
  end

  describe "preflight_all/2" do
    test "returns :ok when every publisher passes" do
      assert :ok =
               Relman.Publisher.preflight_all([
                 %{type: :stub, module: StubOk},
                 %{type: :stub, module: StubOk}
               ])
    end

    test "collects every failure" do
      assert {:error, errs} =
               Relman.Publisher.preflight_all([
                 %{type: :stub, module: StubOk},
                 %{type: :stub, module: StubFail},
                 %{type: :stub, module: StubFail}
               ])

      assert length(errs) == 2
    end

    test "propagates replace option onto specs" do
      defmodule ReplaceSpy do
        @behaviour Relman.Publisher
        def preflight(spec) do
          if spec[:replace], do: :ok, else: {:error, "missing replace"}
        end

        def publish(_s, _t, _a, _v), do: {:ok, nil}
        def fetch(_s, _a, _v, _d), do: {:ok, nil}
      end

      assert :ok =
               Relman.Publisher.preflight_all([%{type: :stub, module: ReplaceSpy}],
                 replace: true
               )
    end
  end

  describe "publish_all/5" do
    test "returns urls in order" do
      assert {:ok, ["stub://ok", "stub://ok"]} =
               Relman.Publisher.publish_all(
                 [
                   %{type: :stub, module: StubOk},
                   %{type: :stub, module: StubOk}
                 ],
                 "tar",
                 :app,
                 "1.0.0"
               )
    end

    test "stops on the first failure" do
      assert {:error, reason} =
               Relman.Publisher.publish_all(
                 [
                   %{type: :stub, module: StubOk},
                   %{type: :stub, module: StubFail},
                   %{type: :stub, module: StubOk}
                 ],
                 "tar",
                 :app,
                 "1"
               )

      assert reason =~ "publish boom"
    end
  end

  describe "fetch_first/5" do
    test "returns the first successful fetch" do
      assert {:ok, "stub://fetched"} =
               Relman.Publisher.fetch_first(
                 [
                   %{type: :stub, module: StubFail},
                   %{type: :stub, module: StubOk}
                 ],
                 :app,
                 "1",
                 "/tmp/dest"
               )
    end

    test "errors when all publishers fail" do
      assert {:error, errs} =
               Relman.Publisher.fetch_first(
                 [
                   %{type: :stub, module: StubFail},
                   %{type: :stub, module: StubFail}
                 ],
                 :app,
                 "1",
                 "/tmp/dest"
               )

      assert length(errs) == 2
    end
  end

  describe "resolve/1" do
    test "maps :github and :file type" do
      assert Relman.Publisher.resolve(%{type: :github}) == Relman.Publisher.Github
      assert Relman.Publisher.resolve(%{type: :file}) == Relman.Publisher.File
    end

    test "honors :module override" do
      assert Relman.Publisher.resolve(%{type: :stub, module: StubOk}) == StubOk
    end

    test "raises on unknown type" do
      assert_raise Mix.Error, fn -> Relman.Publisher.resolve(%{type: :unknown}) end
    end
  end
end
