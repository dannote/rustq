defmodule RustQ.GeneratedTest do
  use ExUnit.Case, async: true

  alias RustQ.Generated

  test "writes generated targets" do
    path = tmp_path("generated.rs")

    assert :ok = Generated.sync!(:helpers, path: path, build: fn -> "fn main() {}\n" end)
    assert File.read!(path) == "fn main() {}\n"
  end

  test "checks fresh generated targets" do
    path = tmp_path("fresh.rs")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "fn main() {}\n")

    assert :ok = Generated.sync!(:helpers, [path: path, content: "fn main() {}\n"], check: true)
  end

  test "raises on stale generated targets" do
    path = tmp_path("stale.rs")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "old\n")

    assert_raise Generated.StaleError, ~r/Run: mix rustq.gen/, fn ->
      Generated.sync!(:helpers, [path: path, content: "new\n"], check: true)
    end
  end

  test "supports custom stale commands" do
    path = tmp_path("stale-custom.rs")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "old\n")

    assert_raise Generated.StaleError, ~r/Run: mix skia.codegen/, fn ->
      Generated.sync!(:helpers, [path: path, content: "new\n"],
        check: true,
        command: "mix skia.codegen"
      )
    end
  end

  test "loads rustq manifests" do
    path = tmp_path("rustq.exs")

    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    [
      generated: [
        helpers: [path: "native/generated.rs", content: "fn main() {}\\n"]
      ]
    ]
    """)

    assert [helpers: [path: "native/generated.rs", content: "fn main() {}\n"]] =
             Generated.load_manifest!(path)
  end

  defp tmp_path(name) do
    Path.join([
      System.tmp_dir!(),
      "rustq-generated-test",
      "#{System.unique_integer([:positive])}",
      name
    ])
  end
end
